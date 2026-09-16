using System.Text.Json;

namespace ControlV.Core;

/// Tiny persisted key/value map — the Windows stand-in for the handful of
/// UserDefaults keys the Mac app uses (install id, install date, counters).
public interface IKeyValueStore
{
    string? GetString(string key);
    void SetString(string key, string? value);
    int GetInt(string key) => int.TryParse(GetString(key), out var v) ? v : 0;
    void SetInt(string key, int value) => SetString(key, value.ToString());
}

public sealed class InMemoryKeyValueStore : IKeyValueStore
{
    private readonly Dictionary<string, string> _values = new();
    public string? GetString(string key) => _values.TryGetValue(key, out var v) ? v : null;
    public void SetString(string key, string? value) { if (value is null) _values.Remove(key); else _values[key] = value; }
}

public sealed class FileKeyValueStore : IKeyValueStore
{
    private readonly string _path;
    private readonly Dictionary<string, string> _values;

    public FileKeyValueStore(string directory)
    {
        Directory.CreateDirectory(directory);
        _path = Path.Combine(directory, "state.json");
        _values = Load();
    }

    public string? GetString(string key) => _values.TryGetValue(key, out var v) ? v : null;

    public void SetString(string key, string? value)
    {
        if (value is null) _values.Remove(key); else _values[key] = value;
        File.WriteAllText(_path, JsonSerializer.Serialize(_values));
    }

    private Dictionary<string, string> Load()
    {
        try
        {
            return File.Exists(_path)
                ? JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(_path)) ?? new()
                : new();
        }
        catch (JsonException) { return new(); }
    }
}
