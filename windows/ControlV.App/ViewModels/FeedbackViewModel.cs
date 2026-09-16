using System.Net.Http;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ControlV.Core;
using ControlV.Core.Models;

namespace ControlV.App.ViewModels;

internal sealed partial class FeedbackViewModel : ObservableObject
{
    private readonly IFeedbackClient _client;
    private readonly FeedbackPromptTracker _tracker;
    private readonly Func<string> _installId;
    private readonly Func<string?> _sessionToken;
    private readonly Func<string?> _contactEmail;

    public FeedbackViewModel(IFeedbackClient client, FeedbackPromptTracker tracker, Func<string> installId, Func<string?> sessionToken, Func<string?> contactEmail)
    { _client = client; _tracker = tracker; _installId = installId; _sessionToken = sessionToken; _contactEmail = contactEmail; }

    public IReadOnlyList<FeedbackCategory> Categories => Enum.GetValues<FeedbackCategory>();
    [ObservableProperty] private int? _rating;
    [ObservableProperty] private FeedbackCategory _category = FeedbackCategory.Idea;
    [ObservableProperty] private string _message = "";
    [ObservableProperty] private string _contactEmailInput = "";
    [ObservableProperty] private bool _isSending;
    [ObservableProperty] private bool _didSend;
    [ObservableProperty] private string? _lastError;
    public bool ShouldInvite => _tracker.ShouldInvite;
    public bool CanSend => !IsSending && (Rating is not null || !string.IsNullOrWhiteSpace(Message));

    partial void OnRatingChanged(int? value) => OnPropertyChanged(nameof(CanSend));
    partial void OnMessageChanged(string value) => OnPropertyChanged(nameof(CanSend));

    public void Reset(int? rating)
    {
        Rating = rating; Category = FeedbackCategory.Idea; Message = ""; DidSend = false; LastError = null;
        ContactEmailInput = _contactEmail() ?? "";
    }

    [RelayCommand] private void SetRating(int value) => Rating = value;
    [RelayCommand] private void Dismiss() { _tracker.MarkDismissed(); OnPropertyChanged(nameof(ShouldInvite)); }

    [RelayCommand] private async Task SendAsync()
    {
        if (!CanSend) return;
        IsSending = true; LastError = null; OnPropertyChanged(nameof(CanSend));
        try
        {
            var email = ContactEmailInput.Trim().ToLowerInvariant();
            await _client.SubmitAsync(new FeedbackSubmission
            {
                Rating = Rating, Category = Category.RawValue(), Message = Message.Trim(),
                ContactEmail = email.Contains('@') ? email : null, InstallId = _installId(), SessionToken = _sessionToken(),
                AppVersion = Services.AppPaths.AppVersion,
            });
            _tracker.MarkSubmitted(); DidSend = true; OnPropertyChanged(nameof(ShouldInvite));
        }
        catch (Exception e) when (e is AuthException or HttpRequestException) { LastError = e.Message; }
        finally { IsSending = false; OnPropertyChanged(nameof(CanSend)); }
    }
}
