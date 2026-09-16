using System.IO;
namespace ControlV.App.Services;

internal static class AppPaths
{
    public static string DataDirectory { get; } =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ctrl+v");

    public static string AppVersion { get; } =
        typeof(AppPaths).Assembly.GetName().Version?.ToString(3) ?? "dev";

    // Same production backend as macOS (values mirror Resources/Info.plist).
    public static Uri AuthBaseUrl { get; } = new("https://hdfhonbgkkiffhkwoivd.functions.supabase.co/");
    public static Uri TranslateEndpoint { get; } = new("https://hdfhonbgkkiffhkwoivd.functions.supabase.co/translate");
}
