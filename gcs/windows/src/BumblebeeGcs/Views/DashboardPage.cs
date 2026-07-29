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

using Microsoft.UI;
using BumblebeeGcs.Controls;
using BumblebeeGcs.Models;
using BumblebeeGcs.Services;
using BumblebeeGcs.Theme;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.UI;

namespace BumblebeeGcs.Views;

/// <summary>Дашборд: hero-плитки, камеры, masonry-панели. Порт DashboardView.swift.</summary>
public sealed class DashboardPage : Grid
{
    private readonly AppState _app;
    private readonly TelemetryStore _t;

    // Hero
    private readonly StatTile _modeTile, _stateTile, _batteryTile, _altTile, _linkTile;

    // Cameras
    private readonly CameraView _front, _bottom, _pip;
    private bool _pipBig;

    // Panels
    private readonly AttitudeView _attitude = new();
    private readonly ReadoutRow _roll = new("Roll"), _pitch = new("Pitch"), _yaw = new("Yaw");
    private readonly LabeledBarRow _batteryBar;
    private readonly ReadoutRow _x, _y, _z, _vx, _vy, _vz;
    private readonly LabeledBarRow _hSpeed, _vSpeed, _angRate, _imuAccel;
    private readonly LabeledBarRow _cpuTemp, _cpuLoad, _load135, _ram;
    private readonly ChartView _chartAlt, _chartSpd, _chartBat;
    private readonly PositionMapView _map;
    private readonly StackPanel _logList = new() { Spacing = Palette.S0 };
    private LogEntry? _lastLogShown = null;
    private bool _logsWereEmpty;

    private readonly Grid _masonry = new() { ColumnSpacing = Palette.S4 };
    private readonly FrameworkElement[] _panels;
    private int _masonryCols;

    private bool _dirty = true, _dirtyMetrics = true;
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer _refresh;
    private readonly Action _onTelemetry, _onMetrics;

    public DashboardPage(AppState app)
    {
        _app = app;
        _t = app.Telemetry;

        // MARK: Hero
        _modeTile = new StatTile("Mode", IconGlyphs.Mode, Palette.Primary);
        _stateTile = new StatTile("State", IconGlyphs.Disarmed, Palette.Muted);
        _batteryTile = new StatTile("Battery", IconGlyphs.Battery, Palette.Muted);
        _altTile = new StatTile("Altitude", IconGlyphs.Altitude, Palette.Primary);
        _linkTile = new StatTile("Link", IconGlyphs.Link, Palette.Warn);
        var hero = new AdaptiveGridPanel { MinItemWidth = 190, Spacing = Palette.S3 };
        foreach (var tile in new[] { _modeTile, _stateTile, _batteryTile, _altTile, _linkTile })
            hero.Children.Add(tile);

        // MARK: Cameras
        _front = new CameraView { Host = app.DroneHost, Topic = "/second_camera/image_raw" };
        _bottom = new CameraView { Host = app.DroneHost, Topic = "/main_camera/image_raw" };
        _pip = new CameraView(showFlipButton: false)
        {
            Host = app.DroneHost,
            Topic = "/aruco_map/image",
            Quality = 50, Fps = 3, StreamWidth = 160, StreamHeight = 120,
            Width = 120, Height = 90,
        };
        _pip.BorderBrush = Palette.Brush(Palette.WithAlpha(Palette.Primary, 0.7));
        _pip.BorderThickness = new Thickness(1);
        _pip.CornerRadius = new CornerRadius(Palette.RMedia);
        _pip.HorizontalAlignment = HorizontalAlignment.Right;
        _pip.VerticalAlignment = VerticalAlignment.Top;
        _pip.Margin = new Thickness(Palette.S2);
        Ui.OnTap(_pip, () =>
        {
            _pipBig = !_pipBig;
            _pip.Width = _pipBig ? 190 : 120;
            _pip.Height = _pipBig ? 142 : 90;
        });

        var tabs = new SegmentedTabs(new[]
        {
            ("Bottom", "/main_camera/image_raw"),
            ("ArUco", "/aruco_detect/debug"),
        }, "/main_camera/image_raw");
        tabs.SelectionChanged += topic => _bottom.SetTopic(topic);

        var bottomStack = new Grid();
        bottomStack.Children.Add(_bottom);
        bottomStack.Children.Add(_pip);

        var cameras = new Grid { ColumnSpacing = Palette.S4 };
        cameras.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        cameras.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var frontCard = CameraCard("Front", null, _front);
        var bottomCard = CameraCard("Bottom", tabs, bottomStack);
        Grid.SetColumn(frontCard, 0);
        Grid.SetColumn(bottomCard, 1);
        cameras.Children.Add(frontCard);
        cameras.Children.Add(bottomCard);
        cameras.VerticalAlignment = VerticalAlignment.Top;

        // MARK: Panels
        _batteryBar = new LabeledBarRow("Battery", Palette.Muted);
        _x = new ReadoutRow("X", Palette.Danger);
        _y = new ReadoutRow("Y", Palette.Ok);
        _z = new ReadoutRow("Z", Palette.Accent2);
        _vx = new ReadoutRow("Vx"); _vy = new ReadoutRow("Vy"); _vz = new ReadoutRow("Vz");
        _hSpeed = new LabeledBarRow("Horiz. Speed", Palette.DataTeal);
        _vSpeed = new LabeledBarRow("Vert. Speed", Palette.DataBlue);
        _angRate = new LabeledBarRow("Angular Rate", Palette.DataOrange);
        _imuAccel = new LabeledBarRow("IMU Accel", Palette.DataGreen);
        _cpuTemp = new LabeledBarRow("CPU Temp", Palette.Muted);
        _cpuLoad = new LabeledBarRow("CPU Load", Palette.Muted);
        _load135 = new LabeledBarRow("Load 1/5/15", Palette.Accent2);
        _ram = new LabeledBarRow("RAM", Palette.Accent2);
        _chartAlt = new ChartView("Altitude (m)", _t.ChartAlt, Palette.DataBlue);
        _chartSpd = new ChartView("Speed (m/s)", _t.ChartSpd, Palette.DataTeal, fixedMin: 0, fixedMax: 5);
        _chartBat = new ChartView("Battery (%)", _t.ChartBat, Palette.DataGreen, fixedMin: 0, fixedMax: 100);
        _map = new PositionMapView(_t.PosTrail);

        var attitudeCentered = new Grid();
        _attitude.HorizontalAlignment = HorizontalAlignment.Center;
        attitudeCentered.Children.Add(_attitude);
        var rpyRow = new Grid { ColumnSpacing = Palette.S3 };
        foreach (var i in Enumerable.Range(0, 3))
            rpyRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        Grid.SetColumn(_roll, 0); Grid.SetColumn(_pitch, 1); Grid.SetColumn(_yaw, 2);
        rpyRow.Children.Add(_roll); rpyRow.Children.Add(_pitch); rpyRow.Children.Add(_yaw);

        var divider = new Border { Height = 1, Background = Palette.Brush(Palette.Hairline) };

        _panels = new FrameworkElement[]
        {
            new PanelCard("Attitude", IconGlyphs.Attitude, attitudeCentered, rpyRow),
            new PanelCard("Telemetry", IconGlyphs.Telemetry, _batteryBar, _x, _y, _z, divider, _vx, _vy, _vz),
            new PanelCard("Flight Data", IconGlyphs.FlightData, _hSpeed, _vSpeed, _angRate, _imuAccel),
            new PanelCard("Raspberry Pi", IconGlyphs.Cpu, _cpuTemp, _cpuLoad, _load135, _ram),
            new PanelCard("Charts", IconGlyphs.Charts, _chartAlt, _chartSpd, _chartBat),
            new PanelCard("Position Map", IconGlyphs.Map, _map),
            new PanelCard("Messages", IconGlyphs.Messages, _logList),
        };

        // MARK: Layout
        var stack = Ui.VStack(Palette.S4, hero, cameras, _masonry);
        stack.Padding = new Thickness(Palette.S4);
        var scroll = new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        Children.Add(scroll);

        SizeChanged += (_, e) => RebuildMasonry(e.NewSize.Width);
        RebuildMasonry(1280);

        // MARK: Refresh
        _onTelemetry = () => _dirty = true;
        _onMetrics = () => _dirtyMetrics = true;
        _t.Updated += _onTelemetry;
        _app.Metrics.Updated += _onMetrics;

        _refresh = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread().CreateTimer();
        _refresh.Interval = TimeSpan.FromMilliseconds(50);
        _refresh.Tick += (_, _) =>
        {
            if (_dirty) { _dirty = false; RefreshTelemetry(); }
            if (_dirtyMetrics) { _dirtyMetrics = false; RefreshMetrics(); }
        };
        _refresh.Start();

        Unloaded += (_, _) =>
        {
            _refresh.Stop();
            _t.Updated -= _onTelemetry;
            _app.Metrics.Updated -= _onMetrics;
        };

        RefreshTelemetry();
        RefreshMetrics();
    }

    /// <summary>
    /// Плотная упаковка панелей по колонкам (Pinterest-style), распределение i % cols
    /// — как в DashboardView.swift.
    /// </summary>
    private void RebuildMasonry(double width)
    {
        var cols = width > 1500 ? 3 : (width > 1040 ? 2 : 1);
        if (cols == _masonryCols) return;
        _masonryCols = cols;

        foreach (var p in _panels)
            if (p.Parent is StackPanel sp) sp.Children.Remove(p);
        _masonry.Children.Clear();
        _masonry.ColumnDefinitions.Clear();

        var columns = new StackPanel[cols];
        for (var c = 0; c < cols; c++)
        {
            _masonry.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            columns[c] = new StackPanel { Spacing = Palette.S4, VerticalAlignment = VerticalAlignment.Top };
            Grid.SetColumn(columns[c], c);
            _masonry.Children.Add(columns[c]);
        }
        for (var i = 0; i < _panels.Length; i++)
            columns[i % cols].Children.Add(_panels[i]);
    }

    private FrameworkElement CameraCard(string title, SegmentedTabs? tabs, FrameworkElement content)
    {
        var header = new Grid { ColumnSpacing = Palette.S2 };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var label = Ui.Text(title.ToUpperInvariant(), Fonts.SectionLbl, Palette.Muted, tracking: 1.1);
        Grid.SetColumn(label, 0);
        header.Children.Add(label);
        if (tabs is not null)
        {
            Grid.SetColumn(tabs, 1);
            header.Children.Add(tabs);
        }

        // 4:3 контейнер: высота следует за шириной.
        var video = new Grid { Background = Palette.Brush(Colors.Black), CornerRadius = new CornerRadius(Palette.RMedia) };
        video.Children.Add(content);
        Ui.ClipRounded(video, (float)Palette.RMedia);
        video.SizeChanged += (_, e) =>
        {
            var h = e.NewSize.Width * 3.0 / 4.0;
            if (double.IsNaN(video.Height) || Math.Abs(video.Height - h) > 0.5) video.Height = h;
        };

        var inner = Ui.VStack(Palette.S2, header, video);
        return Ui.GlassCard(inner, Palette.RPanel, new Thickness(Palette.S3));
    }

    // MARK: - Refresh

    private void RefreshTelemetry()
    {
        _modeTile.Update(_t.Mode.ToUpperInvariant(), Palette.Primary);
        _stateTile.Update(_t.Armed ? "ARMED" : "DISARMED",
            _t.Armed ? Palette.Danger : Palette.Muted,
            _t.Armed ? IconGlyphs.Armed : IconGlyphs.Disarmed);
        _batteryTile.Update(BatteryShort, BatteryColor);
        _altTile.Update($"{_t.PosZ:F2} m", Palette.Primary);
        _linkTile.Update(_t.RosConnected ? "OK" : "—", _t.RosConnected ? Palette.Ok : Palette.Warn);

        _attitude.Update(_t.Roll, _t.Pitch);
        _roll.Set($"{_t.Roll:F1}°");
        _pitch.Set($"{_t.Pitch:F1}°");
        _yaw.Set($"{_t.Yaw:F1}°");

        _batteryBar.Set(BatteryText, _t.BatteryPct ?? 0, BatteryColor);
        _x.Set($"{_t.PosX:+0.000;-0.000;+0.000}");
        _y.Set($"{_t.PosY:+0.000;-0.000;+0.000}");
        _z.Set($"{_t.PosZ:+0.000;-0.000;+0.000}");
        _vx.Set($"{_t.Vx:+0.000;-0.000;+0.000}");
        _vy.Set($"{_t.Vy:+0.000;-0.000;+0.000}");
        _vz.Set($"{_t.Vz:+0.000;-0.000;+0.000}");

        _hSpeed.Set($"{_t.SpeedH:F2} m/s", MathUtil.PctOf(_t.SpeedH, 5));
        _vSpeed.Set($"{_t.SpeedV:F2} m/s", MathUtil.PctOf(_t.SpeedV, 3));
        _angRate.Set($"{_t.GyroMag:F1} °/s", MathUtil.PctOf(_t.GyroMag, 360));
        _imuAccel.Set($"{_t.AccelMag:F2} m/s²", MathUtil.PctOf(_t.AccelMag, 30));

        _chartAlt.Refresh();
        _chartSpd.Refresh();
        _chartBat.Refresh();
        _map.Refresh();

        RefreshLog();
    }

    private void RefreshLog()
    {
        var newest = _t.Logs.FirstOrDefault();
        if (ReferenceEquals(newest, _lastLogShown) && (_t.Logs.Count == 0) == _logsWereEmpty) return;
        _lastLogShown = newest;
        _logsWereEmpty = _t.Logs.Count == 0;

        _logList.Children.Clear();
        if (_t.Logs.Count == 0)
        {
            _logList.Children.Add(Ui.Text("—", Fonts.MonoSmall, Palette.Muted));
            return;
        }
        foreach (var e in _t.Logs)
        {
            var text = Ui.Text(e.Text, Fonts.LogMono, Palette.Text);
            text.TextWrapping = TextWrapping.Wrap;
            var row = new Grid { ColumnSpacing = Palette.S1 + 2 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var time = Ui.Text(e.Time, Fonts.LogMono, Palette.Muted);
            time.VerticalAlignment = VerticalAlignment.Top;
            text.VerticalAlignment = VerticalAlignment.Top;
            Grid.SetColumn(time, 0);
            Grid.SetColumn(text, 1);
            row.Children.Add(time);
            row.Children.Add(text);
            _logList.Children.Add(row);
        }
    }

    private void RefreshMetrics()
    {
        var m = _app.Metrics.Metrics;
        _cpuTemp.Set(m.CpuTemp is double t ? $"{t:F1} °C" : "—", Math.Min(100, m.CpuTemp ?? 0), TempColor(m.CpuTemp));
        _cpuLoad.Set(m.CpuPct is double c ? $"{c:F0}%" : "—", m.CpuPct ?? 0, CpuColor(m.CpuPct));
        _load135.Set(LoadText(m), (m.Load1 ?? 0) / (m.CpuCount ?? 4) * 100);
        _ram.Set(MemText(m), m.MemPct ?? 0);
    }

    // MARK: - Derived (порт batteryShort/batteryText/цветов)

    private string BatteryShort => _t.BatteryPct is double p ? $"{p:F0}%" : "—";

    private string BatteryText
    {
        get
        {
            var v = _t.BatteryVoltage is double bv ? $"{bv:F2} V" : "— V";
            var p = _t.BatteryPct is double bp ? $"{bp:F0}%" : "—";
            return $"{v} · {p}";
        }
    }

    private Color BatteryColor =>
        _t.BatteryPct is not double p ? Palette.Muted :
        p > 55 ? Palette.Ok : (p > 25 ? Palette.Warn : Palette.Danger);

    private static Color TempColor(double? x) =>
        x is not double v ? Palette.Muted : v < 60 ? Palette.Ok : (v < 75 ? Palette.Warn : Palette.Danger);

    private static Color CpuColor(double? x) =>
        x is not double v ? Palette.Muted : v < 60 ? Palette.Ok : (v < 85 ? Palette.Warn : Palette.Danger);

    private static string LoadText(SystemMetrics m) =>
        m.Load1 is double l1 && m.Load5 is double l5 && m.Load15 is double l15
            ? $"{l1:F2} / {l5:F2} / {l15:F2}" : "—";

    private static string MemText(SystemMetrics m) =>
        m.MemUsed is int u && m.MemTotal is int tot && m.MemPct is double p
            ? $"{u} / {tot} MB ({p:F0}%)" : "—";
}
