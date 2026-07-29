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

using Windows.Devices.Enumeration;

namespace BumblebeeGcs.Services;

/// <summary>
/// DNS-SD (Bonjour/mDNS) браузер сервиса дрона `_bumblebee._tcp` — нативный
/// WinRT-аналог NetServiceBrowser. Резолвит каждый найденный сервис в IPv4 и
/// читает дружественное имя из TXT-записи `name`.
/// </summary>
public sealed class DnssdBrowser : IDisposable
{
    private const string Aqs =
        "System.Devices.AepService.ProtocolId:={4526e8c1-8aac-4153-9b16-55e86ada0e54}" +
        " AND System.Devices.Dnssd.ServiceName:=\"_bumblebee._tcp.local\"";

    private static readonly string[] Props =
    {
        "System.Devices.Dnssd.HostName",
        "System.Devices.Dnssd.InstanceName",
        "System.Devices.IpAddress",
        "System.Devices.Dnssd.PortNumber",
        "System.Devices.Dnssd.TextAttributes",
    };

    private readonly DeviceWatcher _watcher;
    private readonly Action<string, string> _onFound; // (ip, name) — на фоновом потоке
    private bool _started;

    public DnssdBrowser(Action<string, string> onFound)
    {
        _onFound = onFound;
        _watcher = DeviceInformation.CreateWatcher(Aqs, Props, DeviceInformationKind.AssociationEndpointService);
        _watcher.Added += (_, info) => Handle(info.Properties);
        // Пустые обработчики обязательны — иначе AEP-watcher бросает исключение.
        _watcher.Updated += (_, update) => Handle(update.Properties);
        _watcher.Removed += (_, _) => { };
        _watcher.EnumerationCompleted += (_, _) => { };
        _watcher.Stopped += (_, _) => { };
    }

    public void Start()
    {
        if (_started) return;
        _started = true;
        try { _watcher.Start(); } catch { _started = false; }
    }

    public void Stop()
    {
        if (!_started) return;
        _started = false;
        try { _watcher.Stop(); } catch { }
    }

    private void Handle(IReadOnlyDictionary<string, object> props)
    {
        var ip = FirstIpv4(props);
        if (ip is null) return;
        var name = TxtName(props)
                   ?? (props.TryGetValue("System.Devices.Dnssd.InstanceName", out var inst) ? inst as string : null)
                   ?? ip;
        _onFound(ip, name);
    }

    private static string? FirstIpv4(IReadOnlyDictionary<string, object> props)
    {
        if (!props.TryGetValue("System.Devices.IpAddress", out var raw)) return null;
        var addrs = raw as string[] ?? (raw is string s ? new[] { s } : null);
        if (addrs is null) return null;
        foreach (var a in addrs)
            if (System.Net.IPAddress.TryParse(a, out var parsed) &&
                parsed.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                return a;
        return null;
    }

    private static string? TxtName(IReadOnlyDictionary<string, object> props)
    {
        if (!props.TryGetValue("System.Devices.Dnssd.TextAttributes", out var raw)) return null;
        if (raw is not string[] txt) return null;
        foreach (var entry in txt)
        {
            var eq = entry.IndexOf('=');
            if (eq > 0 && entry[..eq] == "name")
            {
                var v = entry[(eq + 1)..];
                return string.IsNullOrEmpty(v) ? null : v;
            }
        }
        return null;
    }

    public void Dispose() => Stop();
}
