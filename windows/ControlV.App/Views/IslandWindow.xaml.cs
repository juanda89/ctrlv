using System.Windows;

namespace ControlV.App.Views;

/// Top-center pill shown while a translation runs (the Mac "island").
public partial class IslandWindow : Window
{
    private DateTime _shownAt;
    private static readonly TimeSpan MinimumVisible = TimeSpan.FromMilliseconds(550);

    public IslandWindow() { InitializeComponent(); }

    public void ShowIsland()
    {
        var area = SystemParameters.WorkArea;
        Left = area.Left + (area.Width - Math.Max(ActualWidth, 160)) / 2;
        Top = area.Top + 12;
        _shownAt = DateTime.UtcNow;
        if (!IsVisible) Show();
    }

    public async void HideIsland()
    {
        var elapsed = DateTime.UtcNow - _shownAt;
        if (elapsed < MinimumVisible) await Task.Delay(MinimumVisible - elapsed);
        Hide();
    }
}
