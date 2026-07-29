// Copyright 2026 FutureLab
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

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
