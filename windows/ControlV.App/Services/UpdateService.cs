using Velopack;
using Velopack.Sources;

namespace ControlV.App.Services;

/// Auto-updates via Velopack against the same GitHub Releases that ship the
/// Mac build. No-op when running unpackaged (dev builds).
internal sealed class UpdateService
{
    private const string Repo = "https://github.com/juanda89/ctrlv";
    private static readonly TimeSpan Interval = TimeSpan.FromHours(6);
    private readonly UpdateManager _manager = new(new GithubSource(Repo, null, prerelease: false));
    private PeriodicTimer? _timer;

    public string? LastResult { get; private set; }

    public bool IsInstalled => _manager.IsInstalled;

    public void StartBackgroundChecks()
    {
        if (!IsInstalled) { LastResult = "Not installed (dev build); updates disabled"; return; }
        _ = Task.Run(async () =>
        {
            await Task.Delay(TimeSpan.FromSeconds(30));
            await CheckAndApplyAsync(interactive: false);
            _timer = new PeriodicTimer(Interval);
            while (await _timer.WaitForNextTickAsync()) await CheckAndApplyAsync(interactive: false);
        });
    }

    public async Task<string> CheckAndApplyAsync(bool interactive)
    {
        if (!IsInstalled) return LastResult = "Not installed (dev build); updates disabled";
        try
        {
            var update = await _manager.CheckForUpdatesAsync();
            if (update is null) return LastResult = $"Up to date ({DateTime.Now:HH:mm})";
            await _manager.DownloadUpdatesAsync(update);
            LastResult = $"Downloaded {update.TargetFullRelease.Version}; restarting to apply";
            _manager.ApplyUpdatesAndRestart(update);
            return LastResult;
        }
        catch (Exception e)
        {
            return LastResult = $"Update check failed: {e.Message}";
        }
    }
}
