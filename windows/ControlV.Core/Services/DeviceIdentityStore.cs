namespace ControlV.Core;

/// Stable per-install id used for the trial and rate limits (mirrors the Mac
/// `DeviceIdentityStore`: lowercase UUID, created once).
public sealed class DeviceIdentityStore
{
    private const string Key = "ctrlvInstallID";
    private readonly IKeyValueStore _store;

    public DeviceIdentityStore(IKeyValueStore store) => _store = store;

    public string CurrentInstallId()
    {
        var existing = _store.GetString(Key);
        if (!string.IsNullOrWhiteSpace(existing)) return existing;
        var id = Guid.NewGuid().ToString("D").ToLowerInvariant();
        _store.SetString(Key, id);
        return id;
    }
}
