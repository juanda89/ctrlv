using System.Text.Json.Serialization;

namespace ControlV.Core.Models;

/// One shortcut profile: its own letter, target language, tone and custom prompt.
/// Windows has no legacy flat settings, so the schema starts clean (no keycodes:
/// the letter is the identity; modifiers are fixed app-wide).
public sealed class TranslationProfile
{
    public const int MaxProfiles = 3;

    [JsonPropertyName("id")] public Guid Id { get; init; } = Guid.NewGuid();
    [JsonPropertyName("targetLanguage")] public string TargetLanguageRaw { get; set; } = SupportedLanguage.English.RawValue();
    [JsonPropertyName("tone")] public string ToneRaw { get; set; } = Tone.Original.RawValue();
    [JsonPropertyName("customTonePrompt")] public string CustomTonePrompt { get; set; } = "";
    [JsonPropertyName("shortcutLetter")] public string ShortcutLetter { get; set; } = ShortcutConfiguration.DefaultLetter.ToString();

    [JsonIgnore] public SupportedLanguage TargetLanguage
    {
        get => SupportedLanguages.FromRawValue(TargetLanguageRaw) ?? SupportedLanguage.English;
        set => TargetLanguageRaw = value.RawValue();
    }

    [JsonIgnore] public Tone Tone
    {
        get => Tones.FromRawValue(ToneRaw) ?? Tone.Original;
        set => ToneRaw = value.RawValue();
    }

    [JsonIgnore] public char Letter
    {
        get => ShortcutConfiguration.NormalizeLetter(ShortcutLetter);
        set => ShortcutLetter = ShortcutConfiguration.NormalizeLetter(value.ToString()).ToString();
    }

    public string DisplayLabel => $"{ShortcutConfiguration.ModifierLabel}+{Letter} · {TargetLanguage.RawValue()} · {Tone.RawValue()}";
}
