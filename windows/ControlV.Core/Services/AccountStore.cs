using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using ControlV.Core.Models;

namespace ControlV.Core;

public interface IAccountStore
{
    StoredAccountRecord? Read();
    void Save(StoredAccountRecord record);
    void Delete();
}

public sealed class InMemoryAccountStore : IAccountStore
{
    private StoredAccountRecord? _record;
    public StoredAccountRecord? Read() => _record;
    public void Save(StoredAccountRecord record) => _record = record;
    public void Delete() => _record = null;
}

/// Session record encrypted with DPAPI (user scope): bound to the Windows user
/// and machine, no key material to manage, stable across updates, reboots and
/// network changes (the Mac app once derived its key from the hostname — a bug).
[SupportedOSPlatform("windows")]
public sealed class DpapiAccountStore : IAccountStore
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("ctrlv-account-v1");
    private readonly string _path;

    public DpapiAccountStore(string directory)
    {
        Directory.CreateDirectory(directory);
        _path = Path.Combine(directory, "account.dat");
    }

    public StoredAccountRecord? Read()
    {
        try
        {
            if (!File.Exists(_path)) return null;
            var plain = ProtectedData.Unprotect(File.ReadAllBytes(_path), Entropy, DataProtectionScope.CurrentUser);
            return JsonSerializer.Deserialize<StoredAccountRecord>(plain);
        }
        catch (Exception e) when (e is CryptographicException or JsonException or IOException)
        {
            return null;
        }
    }

    public void Save(StoredAccountRecord record)
    {
        var plain = JsonSerializer.SerializeToUtf8Bytes(record);
        var cipher = ProtectedData.Protect(plain, Entropy, DataProtectionScope.CurrentUser);
        var tmp = _path + ".tmp";
        File.WriteAllBytes(tmp, cipher);
        File.Move(tmp, _path, overwrite: true);
    }

    public void Delete()
    {
        if (File.Exists(_path)) File.Delete(_path);
    }
}
