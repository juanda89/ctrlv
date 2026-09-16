using System.Text.Json.Serialization;

namespace ControlV.Core.Models;

public sealed class AppSettings
{
    public const int CurrentSchemaVersion = 1;

    [JsonPropertyName("schemaVersion")] public int SchemaVersion { get; set; } = CurrentSchemaVersion;
    /// Global behavior flag; applies to every profile (same decision as macOS).
    [JsonPropertyName("autoPaste")] public bool AutoPaste { get; set; } = true;
    [JsonPropertyName("profiles")] public List<TranslationProfile> Profiles { get; set; } = new() { new TranslationProfile() };

    public TranslationProfile Primary => Profiles.Count > 0 ? Profiles[0] : Profiles.Append(new TranslationProfile()).First();
}
