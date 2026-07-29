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

using System.Text;
using System.Text.Json;

namespace BumblebeeGcs.Services;

/// <summary>
/// HTTP-клиент для эндпоинтов дрона `/api/*` (бэкенд wifi_manager.py на :8765).
/// Покрывает LED, звуки/TTS (Entertainment) и wifi/auth (Settings).
/// </summary>
public sealed class DroneApi
{
    public const int Port = 8765;
    public string Host = "";

    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(6) };

    public sealed class ApiException(string message) : Exception(message);

    public readonly record struct WifiStatus(string Mode, string Ssid, string Ip, int Signal);
    public readonly record struct ScanNet(string Ssid, int Signal, bool InUse, string Band, int Freq);

    private async Task<(byte[] Data, int Status)> RequestAsync(HttpMethod method, string path, object? json = null)
    {
        var host = Host;
        if (string.IsNullOrEmpty(host)) throw new ApiException("no drone");
        using var req = new HttpRequestMessage(method, $"http://{host}:{Port}{path}");
        if (json is not null)
            req.Content = new StringContent(JsonSerializer.Serialize(json), Encoding.UTF8, "application/json");
        HttpResponseMessage resp;
        try { resp = await Http.SendAsync(req); }
        catch (Exception ex) { throw new ApiException(ex.Message); }
        using (resp)
        {
            var data = await resp.Content.ReadAsByteArrayAsync();
            return (data, (int)resp.StatusCode);
        }
    }

    private async Task OkAsync(HttpMethod method, string path, object? json = null)
    {
        var (data, status) = await RequestAsync(method, path, json);
        if (status == 200) return;
        throw new ApiException(ErrorFrom(data) ?? $"HTTP {status}");
    }

    static string? ErrorFrom(byte[] data)
    {
        try
        {
            using var doc = JsonDocument.Parse(data);
            if (doc.RootElement.ValueKind == JsonValueKind.Object &&
                doc.RootElement.TryGetProperty("error", out var err) && err.GetString() is string s)
                return s;
        }
        catch { }
        return null;
    }

    static Dictionary<string, JsonElement> ObjectFrom(byte[] data)
    {
        try
        {
            using var doc = JsonDocument.Parse(data);
            if (doc.RootElement.ValueKind == JsonValueKind.Object)
                return doc.RootElement.EnumerateObject().ToDictionary(p => p.Name, p => p.Value.Clone());
        }
        catch { }
        return new Dictionary<string, JsonElement>();
    }

    // MARK: - LED

    public Task LedColorAsync(int r, int g, int b) => OkAsync(HttpMethod.Post, "/api/led/color", new { r, g, b });
    public Task LedAnimationAsync(string name) => OkAsync(HttpMethod.Post, "/api/led/animation", new { name });
    public Task LedResetAsync() => OkAsync(HttpMethod.Post, "/api/led/reset");

    // MARK: - Sounds / TTS

    /// <summary>Возвращает объект ответа сервера (может содержать "tune"/"phonemes").</summary>
    public async Task<Dictionary<string, JsonElement>> PlayTuneAsync(string tune, string format)
    {
        var (data, status) = await RequestAsync(HttpMethod.Post, "/api/sounds/play", new { tune, format });
        var obj = ObjectFrom(data);
        if (status != 200) throw new ApiException(Str(obj, "error") ?? $"HTTP {status}");
        return obj;
    }

    public async Task<Dictionary<string, JsonElement>> TtsAsync(string text, string lang)
    {
        var (data, status) = await RequestAsync(HttpMethod.Post, "/api/sounds/tts", new { text, lang });
        var obj = ObjectFrom(data);
        if (status != 200) throw new ApiException(Str(obj, "error") ?? $"HTTP {status}");
        return obj;
    }

    public static string? Str(Dictionary<string, JsonElement> obj, string key) =>
        obj.TryGetValue(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    // MARK: - WiFi / auth

    public async Task<WifiStatus> WifiStatusAsync()
    {
        var (data, _) = await RequestAsync(HttpMethod.Get, "/api/wifi/status");
        var o = ObjectFrom(data);
        return new WifiStatus(
            Str(o, "mode") ?? "—",
            Str(o, "ssid") ?? "—",
            Str(o, "ip") ?? "—",
            o.TryGetValue("signal", out var s) && s.ValueKind == JsonValueKind.Number ? (int)s.GetDouble() : 0);
    }

    public Task WifiSetModeAsync(string mode) => OkAsync(HttpMethod.Post, "/api/wifi/mode", new { mode });

    public async Task<bool> LoginAsync(string pin)
    {
        var (_, status) = await RequestAsync(HttpMethod.Post, "/api/auth/login", new { pin });
        return status == 200;
    }

    public async Task LogoutAsync()
    {
        try { await RequestAsync(HttpMethod.Post, "/api/auth/logout"); } catch { }
    }

    public async Task<List<ScanNet>> WifiScanAsync()
    {
        var (data, _) = await RequestAsync(HttpMethod.Get, "/api/wifi/scan");
        var list = new List<ScanNet>();
        try
        {
            using var doc = JsonDocument.Parse(data);
            if (doc.RootElement.ValueKind != JsonValueKind.Array) return list;
            foreach (var el in doc.RootElement.EnumerateArray())
            {
                if (el.ValueKind != JsonValueKind.Object) continue;
                list.Add(new ScanNet(
                    el.TryGetProperty("ssid", out var ss) ? ss.GetString() ?? "" : "",
                    el.TryGetProperty("signal", out var sg) && sg.ValueKind == JsonValueKind.Number ? (int)sg.GetDouble() : 0,
                    el.TryGetProperty("in_use", out var iu) && iu.ValueKind == JsonValueKind.True,
                    el.TryGetProperty("band", out var bd) ? bd.GetString() ?? "" : "",
                    el.TryGetProperty("freq", out var fq) && fq.ValueKind == JsonValueKind.Number ? (int)fq.GetDouble() : 0));
            }
        }
        catch { }
        return list;
    }

    public async Task<List<string>> SavedNetworksAsync()
    {
        var (data, _) = await RequestAsync(HttpMethod.Get, "/api/wifi/networks");
        var list = new List<string>();
        try
        {
            using var doc = JsonDocument.Parse(data);
            if (doc.RootElement.ValueKind != JsonValueKind.Array) return list;
            foreach (var el in doc.RootElement.EnumerateArray())
                if (el.ValueKind == JsonValueKind.Object &&
                    el.TryGetProperty("name", out var n) && n.GetString() is string name)
                    list.Add(name);
        }
        catch { }
        return list;
    }

    public Task RemoveNetworkAsync(string ssid) => OkAsync(HttpMethod.Delete, "/api/wifi/network", new { ssid });
    public Task SaveNetworkAsync(string ssid, string password) => OkAsync(HttpMethod.Post, "/api/wifi/save", new { ssid, password });
    public Task ApplyNowAsync(string ssid) => OkAsync(HttpMethod.Post, "/api/wifi/apply-now", new { ssid });
    public Task ApplyBootAsync(string ssid) => OkAsync(HttpMethod.Post, "/api/wifi/apply-boot", new { ssid });
}
