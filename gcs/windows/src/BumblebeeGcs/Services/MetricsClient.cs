using System.Text.Json;
using BumblebeeGcs.Models;
using Microsoft.UI.Dispatching;

namespace BumblebeeGcs.Services;

/// <summary>Опрашивает системные метрики дрона (http://host:8888/) каждые 2 с.</summary>
public sealed class MetricsClient
{
    public SystemMetrics Metrics;
    public event Action? Updated;

    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(2) };

    private readonly DispatcherQueue _dq;
    private DispatcherQueueTimer? _timer;
    private string _host = "";

    public MetricsClient(DispatcherQueue dq) => _dq = dq;

    public void Start(string host)
    {
        Stop();
        _host = host;
        _ = FetchAsync();
        var t = _dq.CreateTimer();
        t.Interval = TimeSpan.FromSeconds(2);
        t.Tick += (_, _) => _ = FetchAsync();
        t.Start();
        _timer = t;
    }

    public void Stop()
    {
        _timer?.Stop();
        _timer = null;
    }

    private async Task FetchAsync()
    {
        var host = _host;
        JsonDocument doc;
        try
        {
            var data = await Http.GetByteArrayAsync($"http://{host}:8888/");
            doc = JsonDocument.Parse(data);
        }
        catch { return; }

        using (doc)
        {
            var o = doc.RootElement;
            if (o.ValueKind != JsonValueKind.Object) return;
            var m = new SystemMetrics
            {
                CpuTemp = Num(o, "cpu_temp"),
                CpuPct = Num(o, "cpu_pct"),
                Load1 = Num(o, "load1"),
                Load5 = Num(o, "load5"),
                Load15 = Num(o, "load15"),
                CpuCount = (int?)Num(o, "cpu_count"),
                MemUsed = (int?)Num(o, "mem_used"),
                MemTotal = (int?)Num(o, "mem_total"),
                MemPct = Num(o, "mem_pct"),
            };
            _dq.TryEnqueue(() =>
            {
                if (_host != host) return;
                Metrics = m;
                Updated?.Invoke();
            });
        }
    }

    static double? Num(JsonElement e, string prop) =>
        e.TryGetProperty(prop, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetDouble() : null;
}
