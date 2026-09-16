using System.Net.Http;
using System.Diagnostics;
using System.Windows;
using ControlV.App.Services;
using ControlV.App.ViewModels;
using ControlV.App.Views;
using ControlV.Core;
using ControlV.Core.Models;
using Hardcodet.Wpf.TaskbarNotification;

namespace ControlV.App;

public partial class App : Application
{
    private TaskbarIcon? _tray;
    private HotkeyService? _hotkeys;
    private FlyoutWindow? _flyout;
    private IslandWindow? _island;
    private TranslationFlow? _flow;
    private LicenseService? _license;
    private ProfileCollection? _profiles;
    private IReadOnlyList<(Guid ProfileId, char Letter, bool Registered)> _hotkeyStatus = Array.Empty<(Guid, char, bool)>();
    private readonly UpdateService _updates = new();

    private void OnStartup(object sender, StartupEventArgs e)
    {
        var dir = AppPaths.DataDirectory;
        var kv = new FileKeyValueStore(dir);
        var settingsStore = new SettingsStore(dir);
        var settings = settingsStore.Load();
        _profiles = new ProfileCollection(settings);
        settingsStore.Save(settings);

        var http = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
        var identity = new DeviceIdentityStore(kv);
        var installId = identity.CurrentInstallId();
        _license = new LicenseService(new MagicCodeAuthClient(http, AppPaths.AuthBaseUrl), new DpapiAccountStore(dir), kv, OpenUrl);
        var provider = new CtrlVCloudProvider(http, AppPaths.TranslateEndpoint, installId, () => _license.StoredSessionToken);
        var clipboard = new ClipboardService();
        var tracker = new FeedbackPromptTracker(kv);
        _flow = new TranslationFlow(_license, provider, new TextCaptureService(clipboard), clipboard, new TrialTranslationService(kv), tracker, () => settings);

        _island = new IslandWindow();
        _flow.Started += () => Dispatcher.Invoke(() => _island.ShowIsland());
        _flow.Finished += () => Dispatcher.Invoke(() => _island.HideIsland());

        var feedback = new FeedbackViewModel(new FeedbackClient(http, AppPaths.AuthBaseUrl), tracker, () => installId,
            () => _license.StoredSessionToken, () => _license.StoredEmail ?? _license.LastSignInEmail);
        var vm = new FlyoutViewModel(_license, settingsStore, settings, _profiles, feedback, _flow, RegisterHotkeys);
        _flyout = new FlyoutWindow(vm, Quit, ShowDebug);

        _hotkeys = new HotkeyService();
        _hotkeys.Triggered += OnHotkey;
        RegisterHotkeys();

        _tray = new TaskbarIcon { ToolTipText = "ctrl+v", Icon = System.Drawing.SystemIcons.Application };
        _tray.TrayLeftMouseUp += (_, _) => ToggleFlyout();
        var menu = new System.Windows.Controls.ContextMenu();
        menu.Items.Add(new System.Windows.Controls.MenuItem { Header = "Open ctrl+v", Command = new CommunityToolkit.Mvvm.Input.RelayCommand(ToggleFlyout) });
        menu.Items.Add(new System.Windows.Controls.MenuItem { Header = "Check for Updates", Command = new CommunityToolkit.Mvvm.Input.AsyncRelayCommand(async () => await _updates.CheckAndApplyAsync(interactive: true)) });
        menu.Items.Add(new System.Windows.Controls.MenuItem { Header = "Debug", Command = new CommunityToolkit.Mvvm.Input.RelayCommand(ShowDebug) });
        menu.Items.Add(new System.Windows.Controls.Separator());
        menu.Items.Add(new System.Windows.Controls.MenuItem { Header = "Quit", Command = new CommunityToolkit.Mvvm.Input.RelayCommand(Quit) });
        _tray.ContextMenu = menu;

        _updates.StartBackgroundChecks();
    }

    private void RegisterHotkeys()
    {
        if (_hotkeys is null || _profiles is null) return;
        _hotkeyStatus = _hotkeys.RegisterAll(_profiles.Profiles.Select(p => (p.Id, p.Letter)));
    }

    private async void OnHotkey(Guid profileId)
    {
        if (_flow is null || _profiles is null) return;
        var profile = _profiles.Profiles.FirstOrDefault(p => p.Id == profileId) ?? _profiles.Primary;
        await _flow.RunAsync(profile);
    }

    private void ToggleFlyout()
    {
        if (_flyout is null) return;
        if (_flyout.IsVisible) _flyout.Hide(); else _flyout.ShowNearTray();
    }

    private void ShowDebug()
    {
        if (_flow is null || _license is null) return;
        new DebugWindow(_flow, _license, _hotkeyStatus).Show();
    }

    private static void OpenUrl(Uri url) => Process.Start(new ProcessStartInfo(url.ToString()) { UseShellExecute = true });

    private void Quit() => Shutdown();

    private void OnExit(object sender, ExitEventArgs e)
    {
        _hotkeys?.Dispose();
        _tray?.Dispose();
    }
}
