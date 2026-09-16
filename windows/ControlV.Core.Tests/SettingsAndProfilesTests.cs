using System.Text.Json;
using ControlV.Core;
using ControlV.Core.Models;
using Xunit;

namespace ControlV.Core.Tests;

public class SettingsAndProfilesTests
{
    [Fact]
    public void Settings_RoundTrip_PreservesProfilesAndRawValues()
    {
        var settings = new AppSettings { AutoPaste = false };
        settings.Profiles[0].TargetLanguage = SupportedLanguage.Chinese;
        settings.Profiles[0].Tone = Tone.Custom;
        settings.Profiles[0].CustomTonePrompt = "pirate";
        settings.Profiles[0].Letter = 'q';

        var json = JsonSerializer.Serialize(settings);
        Assert.Contains("\"targetLanguage\":\"Chinese (Simplified)\"", json);
        Assert.Contains("\"tone\":\"Custom\"", json);
        Assert.Contains("\"shortcutLetter\":\"Q\"", json);

        var back = JsonSerializer.Deserialize<AppSettings>(json)!;
        Assert.False(back.AutoPaste);
        Assert.Equal(SupportedLanguage.Chinese, back.Profiles[0].TargetLanguage);
        Assert.Equal(Tone.Custom, back.Profiles[0].Tone);
        Assert.Equal("pirate", back.Profiles[0].CustomTonePrompt);
        Assert.Equal('Q', back.Profiles[0].Letter);
    }

    [Fact]
    public void SettingsStore_ReturnsDefaults_OnMissingOrCorruptFile()
    {
        var dir = Path.Combine(Path.GetTempPath(), "ctrlv-tests-" + Guid.NewGuid());
        var store = new SettingsStore(dir);
        Assert.Single(store.Load().Profiles);
        File.WriteAllText(Path.Combine(dir, "settings.json"), "{not json");
        Assert.Single(store.Load().Profiles);
        Directory.Delete(dir, recursive: true);
    }

    [Fact]
    public void AddAndSelect_AssignsUniqueLetter_AndSelectsNew()
    {
        var profiles = new ProfileCollection(new AppSettings());
        var second = profiles.AddAndSelect()!;
        Assert.Equal(second.Id, profiles.SelectedId);
        Assert.NotEqual(profiles.Primary.Letter, second.Letter);
        Assert.Equal(1, profiles.SelectedIndex);
    }

    [Fact]
    public void EditingSelected_NeverTouchesOthers()
    {
        var profiles = new ProfileCollection(new AppSettings());
        profiles.AddAndSelect();
        profiles.Selected.TargetLanguage = SupportedLanguage.Spanish;
        profiles.Selected.Tone = Tone.Casual;

        Assert.Equal(SupportedLanguage.English, profiles.Primary.TargetLanguage);
        Assert.Equal(Tone.Original, profiles.Primary.Tone);
        Assert.Equal(SupportedLanguage.Spanish, profiles.Profiles[1].TargetLanguage);
    }

    [Fact]
    public void Letters_CannotCollide_AndPrimaryCannotBeRemoved()
    {
        var profiles = new ProfileCollection(new AppSettings());
        var second = profiles.AddAndSelect()!;
        Assert.False(profiles.SetLetter(second.Id, profiles.Primary.Letter));
        Assert.True(profiles.SetLetter(second.Id, 'S'));
        Assert.Equal('S', second.Letter);
        Assert.False(profiles.Remove(profiles.Primary.Id));
        Assert.True(profiles.Remove(second.Id));
        Assert.Equal(profiles.Primary.Id, profiles.SelectedId);
    }

    [Fact]
    public void Cap_IsThree_AndSanitizeHealsDuplicates()
    {
        var settings = new AppSettings();
        var dup = Guid.NewGuid();
        settings.Profiles = new()
        {
            new TranslationProfile { Id = dup, ShortcutLetter = "V" },
            new TranslationProfile { Id = dup, ShortcutLetter = "V" },
            new TranslationProfile { ShortcutLetter = "V" },
            new TranslationProfile { ShortcutLetter = "9" },
        };
        var profiles = new ProfileCollection(settings);
        Assert.Equal(3, profiles.Profiles.Count);
        Assert.Equal(3, profiles.Profiles.Select(p => p.Id).Distinct().Count());
        Assert.Equal(3, profiles.Profiles.Select(p => p.Letter).Distinct().Count());
        Assert.False(profiles.CanAdd);
        Assert.Null(profiles.AddAndSelect());
    }

    [Fact]
    public void Trial_And_Identity_Helpers()
    {
        var kv = new InMemoryKeyValueStore();
        var identity = new DeviceIdentityStore(kv);
        var id = identity.CurrentInstallId();
        Assert.Equal(id, identity.CurrentInstallId());
        Assert.Equal(id, id.ToLowerInvariant());

        var trial = new TrialTranslationService(kv, () => new DateTimeOffset(2026, 9, 15, 12, 0, 0, TimeSpan.Zero));
        Assert.True(trial.CanTranslate());
        for (var i = 0; i < TrialTranslationService.DailyLimit; i++) trial.RecordTranslation();
        Assert.False(trial.CanTranslate());
        Assert.False(TrialTranslationService.IsTextWithinLimit(new string('a', 3001)));
    }

    [Fact]
    public void PromptBuilder_MatchesMacRules()
    {
        var prompt = PromptBuilder.BuildSystemPrompt("Spanish", Tone.Original);
        Assert.Contains("re-express it in Spanish", prompt);
        Assert.Contains("do NOT use the em-dash", prompt);
        Assert.Contains("Return ONLY the final text", prompt);
        Assert.Contains("Mirror the writer's actual voice", prompt);
        var custom = PromptBuilder.BuildSystemPrompt("Spanish", Tone.Custom, "  corrige tildes  ");
        Assert.Contains("corrige tildes", custom);
    }
}
