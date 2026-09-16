using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using ControlV.Core.Models;

namespace ControlV.Core;

public interface ITranslationProvider
{
    Task<string> TranslateAsync(string text, string systemPrompt, CancellationToken ct = default);
}

/// POSTs to the `translate` Edge Function with the same payload as macOS.
public sealed class CtrlVCloudProvider : ITranslationProvider
{
    private readonly HttpClient _http;
    private readonly Uri _endpoint;
    private readonly string _installId;
    private readonly Func<string?> _sessionToken;

    public CtrlVCloudProvider(HttpClient http, Uri endpoint, string installId, Func<string?> sessionToken)
    {
        _http = http;
        _endpoint = endpoint;
        _installId = installId;
        _sessionToken = sessionToken;
    }

    public async Task<string> TranslateAsync(string text, string systemPrompt, CancellationToken ct = default)
    {
        var body = await PostAsync(new Payload(text, systemPrompt, _installId, Normalize(_sessionToken()), false, "windows"), ct);
        var decoded = TryDecode<TranslationResponse>(body);
        return decoded?.TranslatedText ?? throw TranslationException.Api(200, "Empty translation");
    }

    public Task WarmupAsync(string systemPrompt, CancellationToken ct = default) =>
        PostAsync(new Payload("hola", systemPrompt, _installId, null, true, "windows"), ct);

    private async Task<string> PostAsync(Payload payload, CancellationToken ct)
    {
        HttpResponseMessage response;
        try
        {
            response = await _http.PostAsJsonAsync(_endpoint, payload, ct);
        }
        catch (HttpRequestException e) { throw TranslationException.Network(e); }

        using (response)
        {
            var body = await response.Content.ReadAsStringAsync(ct);
            if (response.StatusCode == (HttpStatusCode)429)
                throw TranslationException.RateLimited(TryDecode<MagicCodeAuthClient.ErrorResponse>(body)?.RetryAfterSeconds);
            if (!response.IsSuccessStatusCode)
                throw TranslationException.Api((int)response.StatusCode, TryDecode<MagicCodeAuthClient.ErrorResponse>(body)?.Error ?? "Translation service unavailable");
            return body;
        }
    }

    private static string? Normalize(string? token) => string.IsNullOrWhiteSpace(token) ? null : token.Trim();

    private static T? TryDecode<T>(string body)
    {
        try { return JsonSerializer.Deserialize<T>(body); } catch (JsonException) { return default; }
    }

    private sealed record Payload(
        [property: JsonPropertyName("text")] string Text,
        [property: JsonPropertyName("systemPrompt")] string SystemPrompt,
        [property: JsonPropertyName("installID")] string InstallId,
        [property: JsonPropertyName("sessionToken"), JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? SessionToken,
        [property: JsonPropertyName("warmupOnly")] bool WarmupOnly,
        [property: JsonPropertyName("platform")] string Platform);

    private sealed record TranslationResponse([property: JsonPropertyName("translatedText")] string TranslatedText,
        [property: JsonPropertyName("model")] string? Model, [property: JsonPropertyName("plan")] string? Plan);
}
