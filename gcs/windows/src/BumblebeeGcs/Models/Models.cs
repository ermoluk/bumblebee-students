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

namespace BumblebeeGcs.Models;

/// <summary>Дрон, к которому оператор уже подключался — «флот» между запусками.</summary>
public sealed record KnownDrone(string Host, string Name)
{
    public string Name { get; set; } = Name;
}

/// <summary>Системные метрики Raspberry Pi (:8888 JSON).</summary>
public struct SystemMetrics
{
    public double? CpuTemp, CpuPct, Load1, Load5, Load15, MemPct;
    public int? CpuCount, MemUsed, MemTotal;
}

public sealed record LogEntry(string Time, string Text);

public readonly record struct Euler(double Roll, double Pitch, double Yaw); // degrees

public static class MathUtil
{
    /// <summary>Кватернион → углы Эйлера в градусах (та же формула, что в Models.swift).</summary>
    public static Euler QuatToEuler(double x, double y, double z, double w)
    {
        var roll = Math.Atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y));
        var sp = Math.Max(-1, Math.Min(1, 2 * (w * y - z * x)));
        var pitch = Math.Asin(sp);
        var yaw = Math.Atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z));
        const double r = 180.0 / Math.PI;
        return new Euler(roll * r, pitch * r, yaw * r);
    }

    public static double PctOf(double v, double max) => Math.Min(100, Math.Abs(v) / max * 100);
}

/// <summary>
/// Хранилище телеметрии — наполняется RosbridgeClient на UI-потоке.
/// Порт TelemetryStore из Models.swift (лимиты: trail 200, chart 120, log 20).
/// </summary>
public sealed class TelemetryStore
{
    // Connection / state
    public bool RosConnected;
    public string Mode = "—";
    public bool Armed;

    // Battery
    public double? BatteryVoltage, BatteryPct;

    // Pose
    public double PosX, PosY, PosZ, Roll, Pitch, Yaw;

    // Velocity
    public double Vx, Vy, Vz;
    public double SpeedH => Math.Sqrt(Vx * Vx + Vy * Vy);
    public double SpeedV => Math.Abs(Vz);

    // IMU
    public double GyroMag;   // deg/s
    public double AccelMag;  // m/s^2

    // Trails / charts
    public readonly List<Windows.Foundation.Point> PosTrail = new();
    public readonly List<double> ChartAlt = new(), ChartSpd = new(), ChartBat = new();

    public readonly List<LogEntry> Logs = new();  // новые сверху
    public string LastUpdate = "—";

    const int PosMax = 200, ChartMax = 120, LogMax = 20;

    /// <summary>Любое значение изменилось — панели перечитывают свои поля.</summary>
    public event Action? Updated;
    /// <summary>RosConnected изменился (точка в сайдбаре).</summary>
    public event Action? ConnectionChanged;

    public void NotifyUpdated() => Updated?.Invoke();

    public void SetRosConnected(bool v)
    {
        if (RosConnected == v) return;
        RosConnected = v;
        ConnectionChanged?.Invoke();
        Updated?.Invoke();
    }

    public void Touch() => LastUpdate = TimeString();

    public void Log(string msg)
    {
        Logs.Insert(0, new LogEntry(TimeString(), msg));
        if (Logs.Count > LogMax) Logs.RemoveRange(LogMax, Logs.Count - LogMax);
    }

    public void PushTrail(double x, double y)
    {
        PosTrail.Add(new Windows.Foundation.Point(x, y));
        if (PosTrail.Count > PosMax) PosTrail.RemoveRange(0, PosTrail.Count - PosMax);
    }

    public static void PushChart(List<double> chart, double v)
    {
        chart.Add(v);
        if (chart.Count > ChartMax) chart.RemoveRange(0, chart.Count - ChartMax);
    }

    public void ResetForReconnect()
    {
        SetRosConnected(false);
        Mode = "—";
        Armed = false;
        BatteryVoltage = null;
        BatteryPct = null;
        Updated?.Invoke();
    }

    public static string TimeString() => DateTime.Now.ToString("HH:mm:ss");
}
