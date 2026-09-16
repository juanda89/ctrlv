using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using ControlV.Core.Models;

namespace ControlV.Core;

public interface IFeedbackClient
{
    Task SubmitAsync(FeedbackSubmission submission, CancellationToken ct = default);
}

public sealed class FeedbackClient : IFeedbackClient
{
    private readonly HttpClient _http;
    private readonly Uri? _baseUrl;

    public FeedbackClient(HttpClient http, Uri? baseUrl) { _http = http; _baseUrl = baseUrl; }

    public async Task SubmitAsync(FeedbackSubmission submission, CancellationToken ct = default)
    {
        if (_baseUrl is null) throw AuthException.MissingBaseUrl();
        using var response = await _http.PostAsJsonAsync(new Uri(_baseUrl, "submit-feedback"), submission, ct);
        var body = await response.Content.ReadAsStringAsync(ct);
        MagicCodeAuthClient.ErrorResponse? error = null;
        try { error = JsonSerializer.Deserialize<MagicCodeAuthClient.ErrorResponse>(body); } catch (JsonException) { }

        if (response.StatusCode == (HttpStatusCode)429) throw AuthException.RateLimited(error?.RetryAfterSeconds);
        if (!response.IsSuccessStatusCode) throw AuthException.Server((int)response.StatusCode, error?.Error ?? "Could not send feedback");
    }
}

/// Mirrors the Mac tracker: invite once after real use, never again after
/// the user answered or dismissed.
public sealed class FeedbackPromptTracker
{
    public const int InviteThreshold = 25;
    private readonly IKeyValueStore _store;

    public FeedbackPromptTracker(IKeyValueStore store) => _store = store;

    public int TranslationCount => _store.GetInt("feedback.translationCount");
    public bool IsDismissed => _store.GetString("feedback.inviteDismissed") == "1";
    public bool HasSubmitted => _store.GetString("feedback.submittedAt") is not null;
    public bool ShouldInvite => !HasSubmitted && !IsDismissed && TranslationCount >= InviteThreshold;

    public void RecordTranslation() => _store.SetInt("feedback.translationCount", TranslationCount + 1);
    public void MarkDismissed() => _store.SetString("feedback.inviteDismissed", "1");
    public void MarkSubmitted(DateTimeOffset? at = null) => _store.SetString("feedback.submittedAt", (at ?? DateTimeOffset.UtcNow).ToString("O"));
}
