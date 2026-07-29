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

using System.Security;
using ManagedNativeWifi;
using Microsoft.UI.Dispatching;
using Windows.Devices.Geolocation;

namespace BumblebeeGcs.Services;

/// <summary>
/// One-tap передача WiFi: найти setup-хотспот дрона в эфире, подключиться к нему,
/// отправить дрону креды домашней сети, дождаться его возврата в общую сеть.
/// Порт WifiHandoff.swift (CoreWLAN → wlanapi через ManagedNativeWifi,
/// CoreLocation → Geolocator: Windows 11 требует геолокацию для скана WiFi).
/// Все публичные члены — UI-поток.
/// </summary>
public sealed class WifiHandoff
{
    /// <summary>Общий PSK setup-хотспота дрона (SSID "Bumblebee-XXXX").</summary>
    public const string HotspotPsk = "12345678";
    /// <summary>Префикс каждого setup-хотспота.</summary>
    public const string HotspotPrefix = "Bumblebee-";
    /// <summary>Дрон в режиме AP (NetworkManager shared) — шлюз по этому адресу.</summary>
    public const string HotspotGatewayHost = "10.42.0.1";

    public enum PhaseKind
    {
        Idle,
        NeedLocationPermission,
        Scanning,
        Picking,           // хотспоты показаны, ждём выбора
        JoiningHotspot,
        PushingCreds,
        WaitingForDrone,
        Done,              // Arg = хост дрона
        Failed,            // Arg = сообщение
    }

    public PhaseKind Phase { get; private set; } = PhaseKind.Idle;
    /// <summary>SSID для JoiningHotspot, хост для Done, сообщение для Failed.</summary>
    public string PhaseArg { get; private set; } = "";

    public bool IsBusy => Phase is PhaseKind.Scanning or PhaseKind.JoiningHotspot
        or PhaseKind.PushingCreds or PhaseKind.WaitingForDrone;

    public sealed record Hotspot(string Ssid, int Rssi);

    public List<Hotspot> Hotspots { get; private set; } = new();
    /// <summary>Текущий SSID этого ПК — сеть, которую отдаём дрону.</summary>
    public string CurrentSsid { get; private set; } = "";
    /// <summary>Система окончательно запретила геолокацию — шлём в Настройки.</summary>
    public bool LocationBlocked { get; private set; }

    public event Action? Changed;

    private readonly DispatcherQueue _dq;

    public WifiHandoff(DispatcherQueue dq) => _dq = dq;

    private void SetPhase(PhaseKind phase, string arg = "")
    {
        Phase = phase;
        PhaseArg = arg;
        Changed?.Invoke();
    }

    public void Reset() => SetPhase(PhaseKind.Idle);

    public void RefreshCurrentSsid()
    {
        try { CurrentSsid = NativeWifi.EnumerateConnectedNetworkSsids().FirstOrDefault()?.ToString() ?? ""; }
        catch { CurrentSsid = ""; }
        Changed?.Invoke();
    }

    // MARK: - Location (нужна для скана WiFi на Windows 11)

    /// <summary>
    /// Разово запросить доступ к геолокации при старте, чтобы разрешение было
    /// выяснено до настройки дрона (аналог requestLocation на маке).
    /// </summary>
    public async Task RequestLocationAsync()
    {
        try
        {
            var access = await Geolocator.RequestAccessAsync();
            LocationBlocked = access == GeolocationAccessStatus.Denied;
        }
        catch { }
        Changed?.Invoke();
    }

    private static Guid? PrimaryInterfaceId()
    {
        try { return NativeWifi.EnumerateInterfaces().FirstOrDefault()?.Id; }
        catch { return null; }
    }

    // MARK: - Scan for drone hotspots

    public async Task ScanHotspotsAsync()
    {
        if (PrimaryInterfaceId() is null)
        {
            SetPhase(PhaseKind.Failed, "No WiFi interface on this PC");
            return;
        }
        try
        {
            var access = await Geolocator.RequestAccessAsync();
            LocationBlocked = access == GeolocationAccessStatus.Denied;
            if (access != GeolocationAccessStatus.Allowed)
            {
                SetPhase(PhaseKind.NeedLocationPermission);
                return;
            }
        }
        catch { }

        SetPhase(PhaseKind.Scanning);
        RefreshCurrentSsid();
        try
        {
            var list = await Task.Run(async () =>
            {
                try { await NativeWifi.ScanNetworksAsync(TimeSpan.FromSeconds(6)); } catch { }
                return NativeWifi.EnumerateBssNetworks()
                    .Where(n => n.Ssid.ToString().StartsWith(HotspotPrefix, StringComparison.Ordinal))
                    .GroupBy(n => n.Ssid.ToString())
                    .Select(g => new Hotspot(g.Key, g.Max(n => n.SignalStrength)))
                    .OrderByDescending(h => h.Rssi)
                    .ToList();
            });
            Hotspots = list;
            SetPhase(PhaseKind.Picking);
        }
        catch (Exception ex)
        {
            SetPhase(PhaseKind.Failed, $"WiFi scan failed: {ex.Message}");
        }
    }

    // MARK: - Full hand-off

    /// <summary>
    /// Подключиться к hotspotSsid, отправить (targetSsid, targetPassword) дрону,
    /// вернуть ПК в свою сеть и дождаться дрона. onDrone(host) при успехе.
    /// </summary>
    public async Task ProvisionAsync(string hotspotSsid, string targetSsid, string targetPassword,
                                     Action<string> onDrone)
    {
        if (PrimaryInterfaceId() is not Guid iface)
        {
            SetPhase(PhaseKind.Failed, "No WiFi interface on this PC");
            return;
        }

        // 1) Подключиться к setup-хотспоту дрона. Первая попытка может упасть,
        //    пока адаптер переключается — ретраим до 4 раз со свежим сканом.
        SetPhase(PhaseKind.JoiningHotspot, hotspotSsid);
        var lastErr = "";
        var joined = false;
        for (var attempt = 1; attempt <= 4 && !joined; attempt++)
        {
            try
            {
                joined = await Task.Run(async () =>
                {
                    var inRange = NativeWifi.EnumerateBssNetworks().Any(n => n.Ssid.ToString() == hotspotSsid);
                    if (!inRange)
                    {
                        try { await NativeWifi.ScanNetworksAsync(TimeSpan.FromSeconds(5)); } catch { }
                        inRange = NativeWifi.EnumerateBssNetworks().Any(n => n.Ssid.ToString() == hotspotSsid);
                    }
                    if (!inRange) throw new InvalidOperationException("hotspot no longer in range");
                    NativeWifi.SetProfile(iface, ProfileType.AllUser,
                        Wpa2PskProfileXml(hotspotSsid, HotspotPsk), null, overwrite: true);
                    return await NativeWifi.ConnectNetworkAsync(iface, hotspotSsid, BssType.Infrastructure,
                        TimeSpan.FromSeconds(15));
                });
                if (!joined) lastErr = "association failed";
            }
            catch (Exception ex)
            {
                lastErr = ex.Message;
            }
            if (!joined && attempt < 4) await Task.Delay(2000);
        }
        if (!joined)
        {
            SetPhase(PhaseKind.Failed, $"Couldn't join {hotspotSsid}: {lastErr}");
            return;
        }

        // 2) Дождаться бэкенда дрона на шлюзе хотспота.
        SetPhase(PhaseKind.PushingCreds);
        var api = new DroneApi { Host = HotspotGatewayHost };
        if (!await WaitForBackendAsync(api))
        {
            SetPhase(PhaseKind.Failed, $"Drone didn't respond on its hotspot ({HotspotGatewayHost})");
            await RejoinAsync(iface, targetSsid);
            return;
        }

        // 3) Отправить дрону WiFi этого ПК и применить (без авторизации).
        try
        {
            await api.SaveNetworkAsync(targetSsid, targetPassword);
            await api.ApplyNowAsync(targetSsid);
        }
        catch (Exception ex)
        {
            SetPhase(PhaseKind.Failed, $"Couldn't set WiFi on the drone: {ex.Message}");
            await RejoinAsync(iface, targetSsid);
            return;
        }

        // 4) Дрон гасит хотспот и уходит на targetSsid; возвращаем ПК в его сеть
        //    (профиль уже сохранён в Windows, раз мы в ней сидели).
        SetPhase(PhaseKind.WaitingForDrone);
        await RejoinAsync(iface, targetSsid);

        // 5) Ждём появления дрона в общей сети через DNS-SD.
        if (await WaitForDroneAsync() is string host)
        {
            SetPhase(PhaseKind.Done, host);
            onDrone(host);
        }
        else
        {
            SetPhase(PhaseKind.Failed, "Drone didn't come back online — check the WiFi password and retry");
        }
    }

    // MARK: - Helpers

    private static async Task RejoinAsync(Guid iface, string homeSsid)
    {
        if (string.IsNullOrEmpty(homeSsid)) return;
        try
        {
            await Task.Run(() =>
                NativeWifi.ConnectNetworkAsync(iface, homeSsid, BssType.Infrastructure, TimeSpan.FromSeconds(20)));
        }
        catch { }
    }

    /// <summary>Поллим бэкенд дрона, пока не ответит (или таймаут).</summary>
    private static async Task<bool> WaitForBackendAsync(DroneApi api, double timeoutSeconds = 25)
    {
        var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
        while (DateTime.UtcNow < deadline)
        {
            try
            {
                await api.WifiStatusAsync();
                return true;
            }
            catch { }
            await Task.Delay(1000);
        }
        return false;
    }

    /// <summary>Ждём любой дрон по DNS-SD, возвращаем его хост/IP.</summary>
    private static async Task<string?> WaitForDroneAsync(double timeoutSeconds = 60)
    {
        var tcs = new TaskCompletionSource<string?>(TaskCreationOptions.RunContinuationsAsynchronously);
        using var browser = new DnssdBrowser((ip, _) => tcs.TrySetResult(ip));
        browser.Start();
        var done = await Task.WhenAny(tcs.Task, Task.Delay(TimeSpan.FromSeconds(timeoutSeconds)));
        return done == tcs.Task ? tcs.Task.Result : null;
    }

    /// <summary>Профиль WPA2-PSK для временного подключения к хотспоту.</summary>
    internal static string Wpa2PskProfileXml(string ssid, string psk)
    {
        var name = SecurityElement.Escape(ssid);
        var key = SecurityElement.Escape(psk);
        return $"""
            <?xml version="1.0"?>
            <WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
                <name>{name}</name>
                <SSIDConfig><SSID><name>{name}</name></SSID></SSIDConfig>
                <connectionType>ESS</connectionType>
                <connectionMode>manual</connectionMode>
                <MSM>
                    <security>
                        <authEncryption>
                            <authentication>WPA2PSK</authentication>
                            <encryption>AES</encryption>
                            <useOneX>false</useOneX>
                        </authEncryption>
                        <sharedKey>
                            <keyType>passPhrase</keyType>
                            <protected>false</protected>
                            <keyMaterial>{key}</keyMaterial>
                        </sharedKey>
                    </security>
                </MSM>
            </WLANProfile>
            """;
    }
}
