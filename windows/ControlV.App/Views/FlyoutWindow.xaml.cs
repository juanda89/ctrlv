using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using ControlV.App.ViewModels;

namespace ControlV.App.Views;

public partial class FlyoutWindow : Window
{
    private readonly Action _quit;
    private readonly Action _showDebug;
    internal FlyoutViewModel ViewModel => (FlyoutViewModel)DataContext;

    internal FlyoutWindow(FlyoutViewModel viewModel, Action quit, Action showDebug)
    {
        InitializeComponent();
        DataContext = viewModel;
        _quit = quit;
        _showDebug = showDebug;
    }

    public async void ShowNearTray()
    {
        var area = SystemParameters.WorkArea;
        Left = area.Right - Width - 12;
        Top = area.Bottom - Height - 12;
        Show();
        Activate();
        await ViewModel.RefreshOnOpenAsync();
    }

    private void OnDeactivated(object? sender, EventArgs e) => Hide();
    private void OnMenuClick(object sender, RoutedEventArgs e) { if (sender is Button b && b.ContextMenu is not null) { b.ContextMenu.PlacementTarget = b; b.ContextMenu.IsOpen = true; } }
    private void OnDebugClick(object sender, RoutedEventArgs e) => _showDebug();
    private void OnQuitClick(object sender, RoutedEventArgs e) => _quit();
    private void OnCloseFeedback(object sender, RoutedEventArgs e) => ViewModel.CloseFeedbackCommand.Execute(null);
    private void OnStarClick(object sender, RoutedEventArgs e) { if (sender is Button b && int.TryParse(b.Tag?.ToString(), out var v)) ViewModel.Feedback.Rating = v; }
    private void OnTabClick(object sender, RoutedEventArgs e)
    {
        if (sender is ToggleButton t && t.DataContext is ProfileTabItem item) { ViewModel.SelectedTab = ViewModel.Tabs.First(x => x.Id == item.Id); }
    }
}
