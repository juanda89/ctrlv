using ControlV.Core;
using ControlV.Core.Models;

namespace ControlV.App.Services;

/// The Windows counterpart of TranslatorViewModel.performTranslation: license
/// gate → capture → trial limits → prompt → translate → clipboard + paste.
internal sealed class TranslationFlow
{
    private readonly LicenseService _license;
    private readonly ITranslationProvider _provider;
    private readonly TextCaptureService _capture;
    private readonly ClipboardService _clipboard;
    private readonly TrialTranslationService _trial;
    private readonly FeedbackPromptTracker _feedbackTracker;
    private readonly Func<AppSettings> _settings;
    private bool _isTranslating;

    public event Action? Started;
    public event Action? Finished;
    public string LastStage { get; private set; } = "Idle";
    public string? LastError { get; private set; }
    public List<string> Events { get; } = new();

    public TranslationFlow(LicenseService license, ITranslationProvider provider, TextCaptureService capture, ClipboardService clipboard,
        TrialTranslationService trial, FeedbackPromptTracker feedbackTracker, Func<AppSettings> settings)
    {
        _license = license; _provider = provider; _capture = capture; _clipboard = clipboard;
        _trial = trial; _feedbackTracker = feedbackTracker; _settings = settings;
    }

    public async Task RunAsync(TranslationProfile profile)
    {
        if (_isTranslating) { Stage("Skipped: already translating"); return; }
        _isTranslating = true;
        Started?.Invoke();
        try
        {
            Stage($"Flow started ({profile.Letter})");
            await _license.RefreshSubscriptionStatusAsync(forceNetwork: false);
            if (!_license.State.CanTranslate) { Fail("Blocked: license", TranslationException.TrialExpired().Message); return; }
            var isTrial = _license.State is LicenseState.Trial;

            var capture = await _capture.CaptureAsync();
            Stage(capture.Stage);
            if (string.IsNullOrWhiteSpace(capture.Text)) { Fail("Blocked: no selected text", TranslationException.NoTextSelected().Message); return; }
            var text = capture.Text!;

            if (isTrial)
            {
                if (!TrialTranslationService.IsTextWithinLimit(text)) { Fail("Blocked: trial text too long", TranslationException.TrialTextTooLong(TrialTranslationService.MaxCharacters / 6).Message); return; }
                if (!_trial.CanTranslate()) { Fail("Blocked: trial quota exceeded", TranslationException.TrialQuotaExceeded().Message); return; }
            }

            var prompt = PromptBuilder.BuildSystemPrompt(profile.TargetLanguage.RawValue(), profile.Tone,
                string.IsNullOrWhiteSpace(profile.CustomTonePrompt) ? null : profile.CustomTonePrompt);
            Stage("Calling ctrl+v Cloud");
            string translated;
            try { translated = await _provider.TranslateAsync(text, prompt); }
            catch (TranslationException e) { Fail("Backend error", e.Message); return; }

            if (isTrial) _trial.RecordTranslation();
            _feedbackTracker.RecordTranslation();

            // Invariant: the translation always lands in the clipboard.
            _clipboard.WriteText(translated);
            if (_settings().AutoPaste && capture.IsEditable)
            {
                await Task.Delay(40);
                _clipboard.SimulatePaste();
                Stage("Output: pasted via clipboard");
            }
            else
            {
                Stage(_settings().AutoPaste ? "Output: copied (non-editable focus)" : "Output: copied to clipboard");
            }
            LastError = null;
        }
        finally
        {
            _isTranslating = false;
            Finished?.Invoke();
        }
    }

    private void Stage(string stage)
    {
        LastStage = stage;
        Events.Add($"{DateTime.Now:HH:mm:ss} {stage}");
        if (Events.Count > 40) Events.RemoveAt(0);
    }

    private void Fail(string stage, string error) { Stage(stage); LastError = error; }
}
