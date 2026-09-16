using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ControlV.App.Services;
using ControlV.Core;
using ControlV.Core.Models;

namespace ControlV.App.ViewModels;

/// Mirrors the Mac popover: status card, profile tabs, preferences for the
/// selected profile, shortcut, global auto-paste, feedback, inline sign-in.
internal sealed partial class FlyoutViewModel : ObservableObject
{
    private readonly LicenseService _license;
    private readonly SettingsStore _settingsStore;
    private readonly AppSettings _settings;
    private readonly ProfileCollection _profiles;
    private readonly Action _hotkeysChanged;

    public FlyoutViewModel(LicenseService license, SettingsStore settingsStore, AppSettings settings, ProfileCollection profiles,
        FeedbackViewModel feedback, TranslationFlow flow, Action hotkeysChanged)
    {
        _license = license; _settingsStore = settingsStore; _settings = settings; _profiles = profiles; _hotkeysChanged = hotkeysChanged;
        Feedback = feedback; Flow = flow;
        _license.StateChanged += _ => RefreshStatus();
        RefreshStatus();
        RefreshProfiles();
    }

    public FeedbackViewModel Feedback { get; }
    public TranslationFlow Flow { get; }
    public IReadOnlyList<SupportedLanguage> Languages => SupportedLanguages.All;
    public IReadOnlyList<Tone> Tones => Core.Models.Tones.All;
    public IReadOnlyList<char> Letters => ShortcutConfiguration.Letters;
    public string ModifierLabel => ShortcutConfiguration.ModifierLabel;

    // ----- status -----
    [ObservableProperty] private string _statusTitle = "";
    [ObservableProperty] private string _statusDetail = "";
    [ObservableProperty] private bool _isActive;
    [ObservableProperty] private bool _isSignedIn;
    [ObservableProperty] private bool _showSignIn;
    [ObservableProperty] private bool _showFeedback;
    [ObservableProperty] private string? _errorMessage;

    // ----- sign-in -----
    [ObservableProperty] private string _emailInput = "";
    [ObservableProperty] private string _codeInput = "";
    public bool IsAwaitingCode => _license.PendingMagicCodeEmail is not null;
    public string SignInTitle => IsAwaitingCode ? "Verify your email" : "Sign in to upgrade";

    // ----- profiles -----
    public ObservableCollection<ProfileTabItem> Tabs { get; } = new();
    [ObservableProperty] private ProfileTabItem? _selectedTab;
    public bool CanAddProfile => _profiles.CanAdd;
    public bool AutoPaste { get => _settings.AutoPaste; set { _settings.AutoPaste = value; OnPropertyChanged(); Persist(); } }

    public SupportedLanguage SelectedLanguage
    {
        get => _profiles.Selected.TargetLanguage;
        set { _profiles.Selected.TargetLanguage = value; OnPropertyChanged(); Persist(); RefreshProfiles(keepSelection: true); }
    }
    public Tone SelectedTone
    {
        get => _profiles.Selected.Tone;
        set { _profiles.Selected.Tone = value; OnPropertyChanged(); OnPropertyChanged(nameof(IsCustomTone)); Persist(); RefreshProfiles(keepSelection: true); }
    }
    public bool IsCustomTone => SelectedTone == Tone.Custom;
    public string CustomTonePrompt
    {
        get => _profiles.Selected.CustomTonePrompt;
        set { _profiles.Selected.CustomTonePrompt = value; OnPropertyChanged(); Persist(); }
    }
    public char SelectedLetter
    {
        get => _profiles.Selected.Letter;
        set
        {
            if (_profiles.SetLetter(_profiles.SelectedId, value)) { ErrorMessage = null; Persist(); _hotkeysChanged(); RefreshProfiles(keepSelection: true); }
            else ErrorMessage = $"Another profile already uses {ModifierLabel}+{char.ToUpperInvariant(value)}. Pick a different letter.";
            OnPropertyChanged();
        }
    }
    public string SelectedProfileName => $"Profile {_profiles.SelectedIndex + 1}";

    partial void OnSelectedTabChanged(ProfileTabItem? value)
    {
        if (value is null) return;
        _profiles.SelectedId = value.Id;
        OnPropertyChanged(nameof(SelectedLanguage)); OnPropertyChanged(nameof(SelectedTone)); OnPropertyChanged(nameof(IsCustomTone));
        OnPropertyChanged(nameof(CustomTonePrompt)); OnPropertyChanged(nameof(SelectedLetter)); OnPropertyChanged(nameof(SelectedProfileName));
        foreach (var t in Tabs) t.IsSelected = t.Id == value.Id;
    }

    [RelayCommand] private void AddProfile()
    {
        if (_profiles.AddAndSelect() is null) return;
        Persist(); _hotkeysChanged(); RefreshProfiles(keepSelection: true);
    }

    [RelayCommand] private void RemoveProfile(ProfileTabItem? tab)
    {
        if (tab is null || !_profiles.Remove(tab.Id)) return;
        Persist(); _hotkeysChanged(); RefreshProfiles();
    }

    // ----- license actions -----
    [RelayCommand] private async Task UpgradeAsync()
    {
        if (!_license.IsSignedIn) { ShowSignIn = true; return; }
        await _license.OpenUpgradeAsync();
        ErrorMessage = _license.LastError;
    }
    [RelayCommand] private Task ManageAsync() => _license.OpenManageSubscriptionAsync();
    [RelayCommand] private void SignOut() { _license.SignOut(); RefreshStatus(); }
    [RelayCommand] private void OpenSignIn() { EmailInput = _license.LastSignInEmail ?? ""; ShowSignIn = true; }
    [RelayCommand] private void CloseSignIn() { _license.CancelPendingSignIn(); ShowSignIn = false; OnPropertyChanged(nameof(IsAwaitingCode)); OnPropertyChanged(nameof(SignInTitle)); }

    [RelayCommand] private async Task SubmitEmailAsync()
    {
        if (await _license.RequestMagicCodeAsync(EmailInput)) { ErrorMessage = null; EmailInput = ""; }
        else ErrorMessage = _license.LastError;
        OnPropertyChanged(nameof(IsAwaitingCode)); OnPropertyChanged(nameof(SignInTitle));
    }

    [RelayCommand] private async Task SubmitCodeAsync()
    {
        if (await _license.VerifyMagicCodeAsync(CodeInput)) { ErrorMessage = null; CodeInput = ""; ShowSignIn = false; }
        else ErrorMessage = _license.LastError;
        OnPropertyChanged(nameof(IsAwaitingCode)); OnPropertyChanged(nameof(SignInTitle));
        RefreshStatus();
    }

    [RelayCommand] private void OpenFeedback(int? rating) { Feedback.Reset(rating); ShowFeedback = true; }
    [RelayCommand] private void CloseFeedback() => ShowFeedback = false;

    public async Task RefreshOnOpenAsync()
    {
        await _license.RefreshSubscriptionStatusAsync(forceNetwork: true);
        RefreshStatus();
    }

    private void RefreshStatus()
    {
        var s = _license.State;
        IsSignedIn = _license.IsSignedIn;
        IsActive = s is LicenseState.Active;
        (StatusTitle, StatusDetail) = s switch
        {
            LicenseState.Active a => (string.IsNullOrEmpty(a.PlanName) ? "Pro" : a.PlanName!, a.IsOfflineGrace ? "Active (offline mode)" : "Active"),
            LicenseState.Trial t => ("Trial", $"{t.DaysRemaining} day{(t.DaysRemaining == 1 ? "" : "s")} left"),
            LicenseState.Expired => ("Trial ended", "Subscribe to keep translating"),
            LicenseState.Invalid i => ("Attention", i.Reason),
            _ => ("Checking…", ""),
        };
        if (_license.StoredEmail is string email) StatusDetail += $" · {email}";
    }

    private void RefreshProfiles(bool keepSelection = false)
    {
        var selectedId = keepSelection ? _profiles.SelectedId : (Guid?)null;
        Tabs.Clear();
        for (var i = 0; i < _profiles.Profiles.Count; i++)
        {
            var p = _profiles.Profiles[i];
            Tabs.Add(new ProfileTabItem(p.Id, $"Profile {i + 1}", $"{ModifierLabel}+{p.Letter}", i > 0) { IsSelected = p.Id == _profiles.SelectedId });
        }
        SelectedTab = Tabs.FirstOrDefault(t => t.Id == (selectedId ?? _profiles.SelectedId)) ?? Tabs.FirstOrDefault();
        OnPropertyChanged(nameof(CanAddProfile));
    }

    private void Persist() => _settingsStore.Save(_settings);
}

internal sealed partial class ProfileTabItem : ObservableObject
{
    public ProfileTabItem(Guid id, string title, string shortcut, bool removable) { Id = id; Title = title; Shortcut = shortcut; Removable = removable; }
    public Guid Id { get; }
    public string Title { get; }
    public string Shortcut { get; }
    public bool Removable { get; }
    [ObservableProperty] private bool _isSelected;
}
