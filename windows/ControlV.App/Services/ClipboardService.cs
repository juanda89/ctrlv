using System.Windows;
using ControlV.App.Interop;

namespace ControlV.App.Services;

/// Clipboard read/write plus simulated Ctrl+C / Ctrl+V. The fallback capture
/// polls the clipboard sequence number instead of sleeping a fixed time: apps
/// that handle copy in JavaScript (Google Docs) write it late and sometimes
/// with a whitespace-only intermediate write — same lesson as on macOS.
internal sealed class ClipboardService
{
    public uint SequenceNumber => NativeMethods.GetClipboardSequenceNumber();

    public string? ReadText()
    {
        try { return Clipboard.ContainsText() ? Clipboard.GetText() : null; }
        catch (Exception e) when (e is System.Runtime.InteropServices.COMException or InvalidOperationException) { return null; }
    }

    public void WriteText(string text)
    {
        for (var attempt = 0; attempt < 5; attempt++)
        {
            try { Clipboard.SetDataObject(text, copy: true); return; }
            catch (System.Runtime.InteropServices.COMException) { Thread.Sleep(20); }
        }
    }

    public void SimulateCopy() => NativeMethods.SendCtrlCombo(NativeMethods.VK_C);
    public void SimulatePaste() => NativeMethods.SendCtrlCombo(NativeMethods.VK_V);

    public async Task<string?> WaitForCopiedTextAsync(uint baseline, TimeSpan? timeout = null, int pollMs = 25)
    {
        var deadline = DateTime.UtcNow + (timeout ?? TimeSpan.FromMilliseconds(600));
        string? lastSeen = null;
        while (DateTime.UtcNow < deadline)
        {
            if (SequenceNumber != baseline)
            {
                lastSeen = ReadText();
                if (!string.IsNullOrWhiteSpace(lastSeen)) return lastSeen;
            }
            await Task.Delay(pollMs);
        }
        return lastSeen;
    }
}
