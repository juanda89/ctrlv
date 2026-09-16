namespace ControlV.Core;

/// Local trial accounting (the server enforces the real limits; this avoids
/// pointless requests). Mirrors the Mac constants.
public sealed class TrialTranslationService
{
    public const int DailyLimit = 50;
    public const int MaxCharacters = 3000;

    private readonly IKeyValueStore _store;
    private readonly Func<DateTimeOffset> _now;

    public TrialTranslationService(IKeyValueStore store, Func<DateTimeOffset>? now = null)
    {
        _store = store;
        _now = now ?? (() => DateTimeOffset.Now);
    }

    public int UsedToday() => _store.GetInt(TodayKey());
    public int RemainingToday() => Math.Max(0, DailyLimit - UsedToday());
    public bool CanTranslate() => UsedToday() < DailyLimit;
    public static bool IsTextWithinLimit(string text) => text.Length <= MaxCharacters;
    public void RecordTranslation() => _store.SetInt(TodayKey(), UsedToday() + 1);

    private string TodayKey() => $"trialTranslations_{_now():yyyy-MM-dd}";
}
