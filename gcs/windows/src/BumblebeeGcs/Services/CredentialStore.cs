using Windows.Security.Credentials;

namespace BumblebeeGcs.Services;

/// <summary>
/// Память для WiFi-пароля, введённого при настройке дрона. Порт AppKeychain:
/// PasswordVault — пер-пользовательское шифрованное хранилище, без промптов.
/// </summary>
public static class CredentialStore
{
    private const string Resource = "com.bumblebee.gcs.wifi";

    public static string? Password(string ssid)
    {
        if (string.IsNullOrEmpty(ssid)) return null;
        try
        {
            var vault = new PasswordVault();
            var cred = vault.Retrieve(Resource, ssid);
            cred.RetrievePassword();
            return cred.Password;
        }
        catch { return null; }
    }

    public static void SetPassword(string password, string ssid)
    {
        if (string.IsNullOrEmpty(ssid)) return;
        try
        {
            var vault = new PasswordVault();
            try { vault.Remove(vault.Retrieve(Resource, ssid)); } catch { }
            if (!string.IsNullOrEmpty(password))
                vault.Add(new PasswordCredential(Resource, ssid, password));
        }
        catch { }
    }
}
