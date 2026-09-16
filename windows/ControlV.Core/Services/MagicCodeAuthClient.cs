using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using ControlV.Core.Models;

namespace ControlV.Core;

public interface IMagicCodeAuthClient
{
    Task RequestMagicCodeAsync(string email, CancellationToken ct = default);
    Task<string> VerifyMagicCodeAsync(string email, string code, CancellationToken ct = default);
    Task<SubscriptionStatus> RefreshSubscriptionStatusAsync(string token, CancellationToken ct = default);
    Task<Uri> CreateCheckoutSessionAsync(string token, CancellationToken ct = default);
    Task<Uri> CreatePortalSessionAsync(string token, CancellationToken ct = default);
}

/// Same endpoints and JSON as the Mac `MagicCodeAuthClient`.
public sealed class MagicCodeAuthClient : IMagicCodeAuthClient
{
    private readonly HttpClient _http;
    private readonly Uri? _baseUrl;

    public MagicCodeAuthClient(HttpClient http, Uri? baseUrl)
    {
        _http = http;
        _baseUrl = baseUrl;
    }

    public Task RequestMagicCodeAsync(string email, CancellationToken ct = default) =>
        PostAsync<EmptyResponse>("request-magic-code", new { email }, null, ct);

    public async Task<string> VerifyMagicCodeAsync(string email, string code, CancellationToken ct = default) =>
        (await PostAsync<SessionTokenResponse>("verify-magic-code", new { email, code }, null, ct)).SessionToken;

    public async Task<SubscriptionStatus> RefreshSubscriptionStatusAsync(string token, CancellationToken ct = default)
    {
        var r = await PostAsync<SubscriptionStatusResponse>("subscription-status", new { }, token, ct);
        return new SubscriptionStatus(SubscriptionStatusValues.Parse(r.Status), r.PlanName, r.TrialDaysRemaining);
    }

    public async Task<Uri> CreateCheckoutSessionAsync(string token, CancellationToken ct = default) =>
        ParseUrl((await PostAsync<UrlResponse>("create-checkout-session", new { }, token, ct)).Url);

    public async Task<Uri> CreatePortalSessionAsync(string token, CancellationToken ct = default) =>
        ParseUrl((await PostAsync<UrlResponse>("create-portal-session", new { }, token, ct)).Url);

    private static Uri ParseUrl(string? url) =>
        Uri.TryCreate(url, UriKind.Absolute, out var uri) ? uri : throw AuthException.InvalidResponse();

    private async Task<T> PostAsync<T>(string path, object payload, string? bearerToken, CancellationToken ct)
    {
        if (_baseUrl is null) throw AuthException.MissingBaseUrl();
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_baseUrl, path)) { Content = JsonContent.Create(payload) };
        request.Headers.Accept.ParseAdd("application/json");
        if (bearerToken is not null) request.Headers.Authorization = new("Bearer", bearerToken);

        using var response = await _http.SendAsync(request, ct);
        var body = await response.Content.ReadAsStringAsync(ct);

        if (response.StatusCode == (HttpStatusCode)429)
            throw AuthException.RateLimited(TryDecode<ErrorResponse>(body)?.RetryAfterSeconds);
        if (!response.IsSuccessStatusCode)
            throw AuthException.Server((int)response.StatusCode, TryDecode<ErrorResponse>(body)?.Error ?? "Request failed");

        return TryDecode<T>(body) ?? throw AuthException.InvalidResponse();
    }

    private static T? TryDecode<T>(string body)
    {
        try { return JsonSerializer.Deserialize<T>(body); } catch (JsonException) { return default; }
    }

    private sealed record EmptyResponse;
    private sealed record SessionTokenResponse([property: JsonPropertyName("sessionToken")] string SessionToken);
    private sealed record SubscriptionStatusResponse([property: JsonPropertyName("status")] string Status,
        [property: JsonPropertyName("planName")] string? PlanName, [property: JsonPropertyName("trialDaysRemaining")] int? TrialDaysRemaining);
    private sealed record UrlResponse([property: JsonPropertyName("url")] string Url);
    internal sealed record ErrorResponse([property: JsonPropertyName("error")] string? Error,
        [property: JsonPropertyName("retry_after_seconds")] int? RetryAfterSeconds);
}
