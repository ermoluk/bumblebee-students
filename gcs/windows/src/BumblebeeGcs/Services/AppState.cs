using BumblebeeGcs.Models;
using Microsoft.UI.Dispatching;

namespace BumblebeeGcs.Services;

/// <summary>Корневое состояние приложения — порт AppState из AppMain.swift.</summary>
public sealed class AppState
{
    public readonly DroneScanner Scanner;
    public readonly TelemetryStore Telemetry = new();
    public readonly MetricsClient Metrics;
    public readonly DroneApi Api = new();
    public readonly WifiHandoff Handoff;
    public readonly RosbridgeClient Ros;

    public string DroneHost { get; private set; } = "";
    public bool Connected { get; private set; }
    public string? LastHost => _settings.LastHost;
    public List<KnownDrone> KnownDrones => _settings.KnownDrones;

    public event Action? ConnectedChanged;

    private readonly AppSettings _settings = AppSettings.Load();

    public AppState(DispatcherQueue dq)
    {
        Scanner = new DroneScanner(dq);
        Metrics = new MetricsClient(dq);
        Handoff = new WifiHandoff(dq);
        Ros = new RosbridgeClient(Telemetry, dq);
    }

    public void Connect(string ip)
    {
        ip = ip.Trim();
        if (ip.Length == 0) return;
        DroneHost = ip;
        Api.Host = ip;
        Ros.Connect(ip);
        Metrics.Start(ip);
        Connected = true;
        _settings.LastHost = ip;
        RememberDrone(ip);
        _settings.Save();
        KeepAwake.Begin();
        ConnectedChanged?.Invoke();
    }

    /// <summary>Upsert дрона во «флот», по хосту. Bonjour-имя приоритетнее.</summary>
    private void RememberDrone(string host)
    {
        var name = Scanner.Found.FirstOrDefault(d => d.Ip == host)?.Name ?? host;
        var existing = _settings.KnownDrones.FirstOrDefault(d => d.Host == host);
        if (existing is not null)
        {
            if (name != host) existing.Name = name;
        }
        else
        {
            _settings.KnownDrones.Add(new KnownDrone(host, name));
        }
    }

    public void Reconnect()
    {
        if (!Connected || DroneHost.Length == 0) return;
        Ros.Connect(DroneHost);
        Metrics.Start(DroneHost);
    }

    public void Disconnect()
    {
        Ros.Disconnect();
        Metrics.Stop();
        Connected = false;
        KeepAwake.End();
        ConnectedChanged?.Invoke();
    }
}
