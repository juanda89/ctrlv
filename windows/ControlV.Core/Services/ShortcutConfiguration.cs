namespace ControlV.Core;

[Flags]
public enum ShortcutModifiers { None = 0, Alt = 1, Control = 2, Shift = 4, Win = 8 }

/// Single source of truth for shortcut letters and the fixed modifier combo.
/// DECISION 6 (Windows plan): Ctrl+Shift+V is "paste as plain text" in Chrome,
/// Edge, Word and Slack. The default modifiers below are provisional until
/// validated on a Windows machine with a Spanish keyboard (AltGr = Ctrl+Alt).
public static class ShortcutConfiguration
{
    public const char DefaultLetter = 'V';
    public static ShortcutModifiers FixedModifiers { get; } = ShortcutModifiers.Control | ShortcutModifiers.Shift;
    public static string ModifierLabel => string.Join("+", Parts());

    public static IReadOnlyList<char> Letters { get; } = Enumerable.Range('A', 26).Select(c => (char)c).ToArray();

    public static bool IsValidLetter(char letter) => letter is >= 'A' and <= 'Z';

    public static char NormalizeLetter(string? raw)
    {
        var upper = (raw ?? "").Trim().ToUpperInvariant();
        return upper.Length == 1 && IsValidLetter(upper[0]) ? upper[0] : DefaultLetter;
    }

    private static IEnumerable<string> Parts()
    {
        if (FixedModifiers.HasFlag(ShortcutModifiers.Win)) yield return "Win";
        if (FixedModifiers.HasFlag(ShortcutModifiers.Control)) yield return "Ctrl";
        if (FixedModifiers.HasFlag(ShortcutModifiers.Alt)) yield return "Alt";
        if (FixedModifiers.HasFlag(ShortcutModifiers.Shift)) yield return "Shift";
    }
}
