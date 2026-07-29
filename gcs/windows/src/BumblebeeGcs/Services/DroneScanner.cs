using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text.Json;
using Microsoft.UI.Dispatching;

namespace BumblebeeGcs.Services;

/// <summary>
/// Обнаружение дронов Bumblebee в локальной сети.
///
/// Основной путь — zero-config DNS-SD (`_bumblebee._tcp`): имя из TXT-записи.
/// Фолбэк — брутфорс-скан /24 подсети (проба rosbridge :9090); таким дронам имя
/// обогащается из метрик-эндпоинта (:8888), иначе остаётся IP.
/// Все мутации `Found` — на UI-потоке.
/// </summary>
public sealed class DroneScanner
{
    public sealed class Drone
    {
        public required string Ip { get; init; }
        public required string Name { get; set; }
        /// <summary>Имя пришло из Bonjour TXT — субнет-скан не должен его затирать.</summary>
        public bool Bonjour { get; set; }
    }

    public readonly List<Drone> Found = new();
    public bool Scanning { get; private set; }
    /// <summary>true после первого завершённого скана — отличает «ещё не искали» от «не нашли».</summary>
    public bool HasScanned { get; private set; }

    public event Action? Changed;

    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(1.5) };

    private readonly DispatcherQueue _dq;
    private DnssdBrowser? _bonjour;

    public DroneScanner(DispatcherQueue dq) => _dq = dq;

    /// <summary>Непрерывное Bonjour-обнаружение. Повторный вызов безопасен.</summary>
    public void StartDiscovery()
    {
        if (_bonjour is not null) return;
        _bonjour = new DnssdBrowser((ip, name) => _dq.TryEnqueue(() => UpsertBonjour(ip, name)));
        _bonjour.Start();
    }

    private void UpsertBonjour(string ip, string name)
    {
        var display = string.IsNullOrEmpty(name) ? ip : name;
        var existing = Found.FirstOrDefault(d => d.Ip == ip);
        if (existing is not null)
        {
            if (existing.Name == display && existing.Bonjour) return;
            existing.Name = display;
            existing.Bonjour = true;
        }
        else
        {
            Found.Add(new Drone { Ip = ip, Name = display, Bonjour = true });
            SortFound();
        }
        Changed?.Invoke();
    }

    public void Scan()
    {
        if (Scanning) return;
        var prefix = LocalSubnetPrefix();
        if (prefix is null)
        {
            HasScanned = true;
            Changed?.Invoke();
            return;
        }
        Scanning = true;
        Found.Clear();
        Changed?.Invoke();

        _ = Task.Run(async () =>
        {
            using var gate = new SemaphoreSlim(48); // потолок одновременных сокетов
            var tasks = new List<Task>(254);
            for (var i = 1; i <= 254; i++)
            {
                var ip = $"{prefix}{i}";
                await gate.WaitAsync();
                tasks.Add(Task.Run(async () =>
                {
                    try
                    {
                        if (await ProbeAsync(ip, 9090, TimeSpan.FromMilliseconds(600)))
                            _dq.TryEnqueue(() => Add(ip));
                    }
                    finally { gate.Release(); }
                }));
            }
            await Task.WhenAll(tasks);
            _dq.TryEnqueue(() =>
            {
                Scanning = false;
                HasScanned = true;
                Changed?.Invoke();
            });
        });
    }

    /// <summary>Разовая проверка доступности хоста — открыт ли rosbridge (:9090)?</summary>
    public static Task<bool> IsReachableAsync(string ip, double timeoutSeconds = 1.0) =>
        ProbeAsync(ip, 9090, TimeSpan.FromSeconds(timeoutSeconds));

    private void Add(string ip)
    {
        if (Found.Any(d => d.Ip == ip)) return;
        Found.Add(new Drone { Ip = ip, Name = ip });
        SortFound();
        Changed?.Invoke();
        _ = EnrichNameAsync(ip);
    }

    private void SortFound()
    {
        Found.Sort((a, b) => CompareIps(a.Ip, b.Ip));
        static int CompareIps(string x, string y)
        {
            if (IPAddress.TryParse(x, out var ax) && IPAddress.TryParse(y, out var ay))
            {
                var bx = ax.GetAddressBytes();
                var by = ay.GetAddressBytes();
                for (var i = 0; i < Math.Min(bx.Length, by.Length); i++)
                    if (bx[i] != by[i]) return bx[i].CompareTo(by[i]);
                return bx.Length.CompareTo(by.Length);
            }
            return string.CompareOrdinal(x, y);
        }
    }

    /// <summary>Best-effort: подтянуть hostname из метрик-JSON для красивой подписи.</summary>
    private async Task EnrichNameAsync(string ip)
    {
        string? name = null;
        try
        {
            var data = await Http.GetByteArrayAsync($"http://{ip}:8888/");
            using var doc = JsonDocument.Parse(data);
            var o = doc.RootElement;
            if (o.ValueKind == JsonValueKind.Object)
            {
                if (o.TryGetProperty("hostname", out var h) && h.ValueKind == JsonValueKind.String) name = h.GetString();
                else if (o.TryGetProperty("name", out var n) && n.ValueKind == JsonValueKind.String) name = n.GetString();
            }
        }
        catch { return; }
        if (string.IsNullOrEmpty(name)) return;
        _dq.TryEnqueue(() =>
        {
            var d = Found.FirstOrDefault(d => d.Ip == ip);
            if (d is not null && !d.Bonjour)
            {
                d.Name = $"{name} ({ip})";
                Changed?.Invoke();
            }
        });
    }

    // MARK: - TCP probe

    private static async Task<bool> ProbeAsync(string ip, int port, TimeSpan timeout)
    {
        using var socket = new Socket(AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
        using var cts = new CancellationTokenSource(timeout);
        try
        {
            await socket.ConnectAsync(ip, port, cts.Token);
            return true;
        }
        catch { return false; }
    }

    // MARK: - Subnet discovery

    /// <summary>«x.y.z.» для основного IPv4-интерфейса, или null.</summary>
    public static string? LocalSubnetPrefix()
    {
        var candidates = NetworkInterface.GetAllNetworkInterfaces()
            .Where(n => n.OperationalStatus == OperationalStatus.Up &&
                        n.NetworkInterfaceType != NetworkInterfaceType.Loopback &&
                        n.NetworkInterfaceType != NetworkInterfaceType.Tunnel)
            // WiFi предпочтительнее ethernet, остальное — в конце.
            .OrderBy(n => n.NetworkInterfaceType switch
            {
                NetworkInterfaceType.Wireless80211 => 0,
                NetworkInterfaceType.Ethernet => 1,
                _ => 2,
            });

        foreach (var nic in candidates)
        {
            foreach (var addr in nic.GetIPProperties().UnicastAddresses)
            {
                if (addr.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                var bytes = addr.Address.GetAddressBytes();
                if (bytes[0] == 169 && bytes[1] == 254) continue; // link-local
                return $"{bytes[0]}.{bytes[1]}.{bytes[2]}.";
            }
        }
        return null;
    }
}
