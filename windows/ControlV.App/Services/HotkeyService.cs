using System.Windows.Interop;
using ControlV.App.Interop;
using ControlV.Core;

namespace ControlV.App.Services;

/// One RegisterHotKey per profile, dispatched by profile id (mirrors the Mac
/// HotkeyService). Uses a message-only HwndSource so no window is needed.
internal sealed class HotkeyService : IDisposable
{
    private readonly HwndSource _source;
    private readonly Dictionary<int, Guid> _idsToProfiles = new();
    private int _nextId = 1;

    public event Action<Guid>? Triggered;

    public HotkeyService()
    {
        _source = new HwndSource(new HwndSourceParameters("ctrlv-hotkeys") { WindowStyle = 0, Width = 0, Height = 0, ParentWindow = new IntPtr(-3) /* HWND_MESSAGE */ });
        _source.AddHook(WndProc);
    }

    public IReadOnlyList<(Guid ProfileId, char Letter, bool Registered)> RegisterAll(IEnumerable<(Guid ProfileId, char Letter)> bindings)
    {
        UnregisterAll();
        var results = new List<(Guid, char, bool)>();
        foreach (var (profileId, letter) in bindings)
        {
            var id = _nextId++;
            var ok = NativeMethods.RegisterHotKey(_source.Handle, id, ToNative(ShortcutConfiguration.FixedModifiers) | NativeMethods.MOD_NOREPEAT, char.ToUpperInvariant(letter));
            if (ok) _idsToProfiles[id] = profileId;
            results.Add((profileId, letter, ok));
        }
        return results;
    }

    public void UnregisterAll()
    {
        foreach (var id in _idsToProfiles.Keys) NativeMethods.UnregisterHotKey(_source.Handle, id);
        _idsToProfiles.Clear();
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == NativeMethods.WM_HOTKEY && _idsToProfiles.TryGetValue(wParam.ToInt32(), out var profileId))
        {
            handled = true;
            Triggered?.Invoke(profileId);
        }
        return IntPtr.Zero;
    }

    private static uint ToNative(ShortcutModifiers m) =>
        (m.HasFlag(ShortcutModifiers.Alt) ? NativeMethods.MOD_ALT : 0) |
        (m.HasFlag(ShortcutModifiers.Control) ? NativeMethods.MOD_CONTROL : 0) |
        (m.HasFlag(ShortcutModifiers.Shift) ? NativeMethods.MOD_SHIFT : 0) |
        (m.HasFlag(ShortcutModifiers.Win) ? NativeMethods.MOD_WIN : 0);

    public void Dispose()
    {
        UnregisterAll();
        _source.RemoveHook(WndProc);
        _source.Dispose();
    }
}
