namespace ControlV.Core.Models;

/// Mirrors Swift `SupportedLanguage`. Raw values are the exact strings the
/// server prompt and the Mac settings use — keep them identical.
public enum SupportedLanguage { English, Spanish, French, German, Portuguese, Italian, Dutch, Russian, Chinese, Japanese, Korean, Arabic }

public static class SupportedLanguages
{
    private static readonly (SupportedLanguage Language, string Raw, string Bcp47)[] Table =
    {
        (SupportedLanguage.English, "English", "en"),
        (SupportedLanguage.Spanish, "Spanish", "es"),
        (SupportedLanguage.French, "French", "fr"),
        (SupportedLanguage.German, "German", "de"),
        (SupportedLanguage.Portuguese, "Portuguese", "pt"),
        (SupportedLanguage.Italian, "Italian", "it"),
        (SupportedLanguage.Dutch, "Dutch", "nl"),
        (SupportedLanguage.Russian, "Russian", "ru"),
        (SupportedLanguage.Chinese, "Chinese (Simplified)", "zh-Hans"),
        (SupportedLanguage.Japanese, "Japanese", "ja"),
        (SupportedLanguage.Korean, "Korean", "ko"),
        (SupportedLanguage.Arabic, "Arabic", "ar"),
    };

    public static IReadOnlyList<SupportedLanguage> All { get; } = Table.Select(t => t.Language).ToArray();
    public static string RawValue(this SupportedLanguage language) => Table.First(t => t.Language == language).Raw;
    public static string Bcp47(this SupportedLanguage language) => Table.First(t => t.Language == language).Bcp47;

    public static SupportedLanguage? FromRawValue(string? raw) =>
        Table.Where(t => string.Equals(t.Raw, raw, StringComparison.Ordinal)).Select(t => (SupportedLanguage?)t.Language).FirstOrDefault();
}
