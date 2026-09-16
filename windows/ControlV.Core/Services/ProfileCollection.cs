using ControlV.Core.Models;

namespace ControlV.Core;

/// Profile CRUD + selection rules, ported from the Mac `SettingsViewModel` so the
/// WPF view model stays thin and these invariants are unit-tested on any OS:
/// - never more than MaxProfiles, never zero
/// - two profiles can never share a letter (SetLetter is a no-op on collision)
/// - the primary (index 0) cannot be removed
/// - selection always resolves to an existing profile (falls back to primary)
public sealed class ProfileCollection
{
    private readonly AppSettings _settings;
    private Guid? _selectedId;

    public ProfileCollection(AppSettings settings)
    {
        _settings = settings;
        Sanitize();
    }

    public IReadOnlyList<TranslationProfile> Profiles => _settings.Profiles;
    public TranslationProfile Primary => _settings.Profiles[0];
    public bool CanAdd => _settings.Profiles.Count < TranslationProfile.MaxProfiles;

    public Guid SelectedId
    {
        get => _selectedId is Guid id && _settings.Profiles.Any(p => p.Id == id) ? id : Primary.Id;
        set { if (_settings.Profiles.Any(p => p.Id == value)) _selectedId = value; }
    }

    public TranslationProfile Selected => _settings.Profiles.First(p => p.Id == SelectedId);
    public int SelectedIndex => _settings.Profiles.FindIndex(p => p.Id == SelectedId);

    public TranslationProfile? AddAndSelect()
    {
        if (!CanAdd) return null;
        var profile = new TranslationProfile { Letter = FirstFreeLetter() };
        _settings.Profiles.Add(profile);
        _selectedId = profile.Id;
        return profile;
    }

    public bool Remove(Guid id)
    {
        var index = _settings.Profiles.FindIndex(p => p.Id == id);
        if (index <= 0) return false;
        _settings.Profiles.RemoveAt(index);
        if (_selectedId == id) _selectedId = null;
        return true;
    }

    public bool IsLetterAvailable(char letter, Guid excludingProfile) =>
        !_settings.Profiles.Any(p => p.Id != excludingProfile && p.Letter == char.ToUpperInvariant(letter));

    /// No-op when another profile already owns the letter; callers surface the error.
    public bool SetLetter(Guid id, char letter)
    {
        letter = char.ToUpperInvariant(letter);
        if (!ShortcutConfiguration.IsValidLetter(letter)) return false;
        var profile = _settings.Profiles.FirstOrDefault(p => p.Id == id);
        if (profile is null || !IsLetterAvailable(letter, id)) return false;
        profile.Letter = letter;
        return true;
    }

    private char FirstFreeLetter()
    {
        var used = _settings.Profiles.Select(p => p.Letter).ToHashSet();
        return ShortcutConfiguration.Letters.FirstOrDefault(l => !used.Contains(l), ShortcutConfiguration.DefaultLetter);
    }

    /// Self-heal persisted state: drop duplicate ids, dedupe letters, never empty.
    private void Sanitize()
    {
        var seen = new HashSet<Guid>();
        _settings.Profiles = _settings.Profiles.Where(p => seen.Add(p.Id)).ToList();
        var usedLetters = new HashSet<char>();
        foreach (var p in _settings.Profiles)
        {
            if (!ShortcutConfiguration.IsValidLetter(p.Letter) || usedLetters.Contains(p.Letter))
                p.Letter = ShortcutConfiguration.Letters.First(l => !usedLetters.Contains(l));
            usedLetters.Add(p.Letter);
        }
        if (_settings.Profiles.Count == 0) _settings.Profiles.Add(new TranslationProfile());
        if (_settings.Profiles.Count > TranslationProfile.MaxProfiles)
            _settings.Profiles = _settings.Profiles.Take(TranslationProfile.MaxProfiles).ToList();
    }
}
