using System.Text.Json.Serialization;

namespace ControlV.Core.Models;

public enum FeedbackCategory { Bug, Idea, Praise, Other }

public static class FeedbackCategories
{
    public static string RawValue(this FeedbackCategory c) => c.ToString().ToLowerInvariant();
    public static string Label(this FeedbackCategory c) => c switch
    {
        FeedbackCategory.Bug => "Bug", FeedbackCategory.Idea => "Idea", FeedbackCategory.Praise => "Love it", _ => "Other",
    };
}

/// Exactly the JSON `submit-feedback` expects (same as the Mac client).
public sealed class FeedbackSubmission
{
    [JsonPropertyName("rating")] public int? Rating { get; set; }
    [JsonPropertyName("category")] public string Category { get; set; } = FeedbackCategory.Idea.RawValue();
    [JsonPropertyName("message")] public string Message { get; set; } = "";
    [JsonPropertyName("contactEmail")] public string? ContactEmail { get; set; }
    [JsonPropertyName("installID")] public string InstallId { get; set; } = "";
    [JsonPropertyName("sessionToken")] public string? SessionToken { get; set; }
    [JsonPropertyName("appVersion")] public string AppVersion { get; set; } = "";
    [JsonPropertyName("platform")] public string Platform { get; set; } = "windows";
}
