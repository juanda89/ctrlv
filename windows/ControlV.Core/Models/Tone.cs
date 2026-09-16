namespace ControlV.Core.Models;

/// Mirrors Swift `Tone`. Raw values must stay identical to the Mac app.
public enum Tone { Original, Formal, Casual, Concise, Custom }

public static class Tones
{
    public static IReadOnlyList<Tone> All { get; } = Enum.GetValues<Tone>();
    public static string RawValue(this Tone tone) => tone.ToString();
    public static Tone? FromRawValue(string? raw) =>
        Enum.TryParse<Tone>(raw, ignoreCase: false, out var tone) ? tone : null;
}
