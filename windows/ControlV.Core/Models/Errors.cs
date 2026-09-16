namespace ControlV.Core.Models;

/// Mirrors Swift `AuthError`. Messages are the ones shown to users.
public sealed class AuthException : Exception
{
    public enum Kind { MissingBaseUrl, InvalidResponse, RateLimited, Server }

    public Kind ErrorKind { get; }
    public int? RetryAfterSeconds { get; }
    public int? StatusCode { get; }

    private AuthException(Kind kind, string message, int? retryAfterSeconds = null, int? statusCode = null) : base(message)
    {
        ErrorKind = kind;
        RetryAfterSeconds = retryAfterSeconds;
        StatusCode = statusCode;
    }

    public static AuthException MissingBaseUrl() => new(Kind.MissingBaseUrl, "Auth service not configured");
    public static AuthException InvalidResponse() => new(Kind.InvalidResponse, "Invalid server response");
    public static AuthException Server(int statusCode, string message) => new(Kind.Server, message, statusCode: statusCode);

    public static AuthException RateLimited(int? retryAfterSeconds)
    {
        if (retryAfterSeconds is int retry)
        {
            var minutes = Math.Max(1, retry / 60);
            return new AuthException(Kind.RateLimited, $"Too many requests. Try again in {minutes} minute{(minutes == 1 ? "" : "s")}.", retry);
        }
        return new AuthException(Kind.RateLimited, "Too many requests. Try again in a few minutes.");
    }
}

/// Mirrors the subset of Swift `TranslationError` the hosted flow can raise.
public sealed class TranslationException : Exception
{
    public enum Kind { NoTextSelected, BackendNotConfigured, Network, Api, RateLimited, TrialExpired, TrialQuotaExceeded, TrialTextTooLong, ReplacementFailed }

    public Kind ErrorKind { get; }
    public int? StatusCode { get; }
    public int? RetryAfterSeconds { get; }

    public TranslationException(Kind kind, string message, int? statusCode = null, int? retryAfterSeconds = null, Exception? inner = null) : base(message, inner)
    {
        ErrorKind = kind;
        StatusCode = statusCode;
        RetryAfterSeconds = retryAfterSeconds;
    }

    public static TranslationException NoTextSelected() => new(Kind.NoTextSelected, "No text selected");
    public static TranslationException BackendNotConfigured() => new(Kind.BackendNotConfigured, "Translation service is not configured yet.");
    public static TranslationException Network(Exception inner) => new(Kind.Network, $"Network error: {inner.Message}", inner: inner);
    public static TranslationException Api(int statusCode, string message) => new(Kind.Api, $"API error ({statusCode}): {message}", statusCode);
    public static TranslationException RateLimited(int? retryAfter) => new(Kind.RateLimited,
        retryAfter is int r ? $"ctrl+v Cloud rate limited. Retry in {r}s." : "ctrl+v Cloud rate limited. Try again shortly.", retryAfterSeconds: retryAfter);
    public static TranslationException TrialExpired() => new(Kind.TrialExpired, "Trial expired. Subscribe to continue.");
    public static TranslationException TrialQuotaExceeded() => new(Kind.TrialQuotaExceeded, "Daily trial limit reached (50 translations). Upgrade to continue translating.");
    public static TranslationException TrialTextTooLong(int maxWords) => new(Kind.TrialTextTooLong, $"Text exceeds trial limit of {maxWords} words. Upgrade to translate longer selections.");
    public static TranslationException ReplacementFailed() => new(Kind.ReplacementFailed, "Could not replace selected text");
}
