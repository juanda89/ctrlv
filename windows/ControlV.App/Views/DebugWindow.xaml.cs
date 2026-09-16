using System.Windows;
using ControlV.App.Services;
using ControlV.Core;

namespace ControlV.App.Views;

public partial class DebugWindow : Window
{
    internal DebugWindow(TranslationFlow flow, LicenseService license, IReadOnlyList<(Guid ProfileId, char Letter, bool Registered)> hotkeys)
    {
        InitializeComponent();
        Summary.Text = $"Last stage: {flow.LastStage}\nLast error: {flow.LastError ?? "none"}\nLicense: {license.State.StatusText}\n" +
                       $"Hotkeys: {string.Join(", ", hotkeys.Select(h => $"{ShortcutConfiguration.ModifierLabel}+{h.Letter}{(h.Registered ? "" : " (FAILED to register)")}"))}\nVersion: {AppPaths.AppVersion}";
        EventList.ItemsSource = flow.Events.AsEnumerable().Reverse().ToList();
    }
}
