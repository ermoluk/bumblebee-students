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
using BumblebeeGcs.Services;
using BumblebeeGcs.Theme;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.UI;

namespace BumblebeeGcs.Views;

/// <summary>WiFi дрона: статус, скан, сохранённые сети, добавление. Порт SettingsView.swift.</summary>
public sealed class SettingsPage : Grid
{
    private readonly AppState _app;

    private DroneApi.WifiStatus? _status;
    private readonly StackPanel _statusRows = new() { Spacing = Palette.S3 };
    private readonly StackPanel _scanRows = new() { Spacing = Palette.S3 };
    private readonly StackPanel _savedRows = new() { Spacing = Palette.S3 };
    private readonly ProgressRing _scanRing = new() { Width = 14, Height = 14, IsActive = true, Visibility = Visibility.Collapsed };
    private readonly GlassTextField _addSsid, _addPass;
    private readonly StatusBanner _msg = new();
    private bool _scanning;

    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer _statusTimer;

    public SettingsPage(AppState app)
    {
        _app = app;

        // MARK: Panels
        var statusPanel = new PanelCard("WiFi Status", IconGlyphs.Wifi, _statusRows);

        var scanBtn = Ui.GhostButton("Scan", DoScan);
        var scanHeader = Ui.HStack(Palette.S2, scanBtn, _scanRing);
        var scanPanel = new PanelCard("Available Networks", IconGlyphs.Antenna, scanHeader, _scanRows);

        var savedPanel = new PanelCard("Saved Networks", IconGlyphs.Bookmark, _savedRows);

        _addSsid = new GlassTextField("SSID", IconGlyphs.Wifi);
        _addPass = new GlassTextField("Password", IconGlyphs.Key, secure: true);
        var applyNow = Ui.AccentButton("Save + Apply Now", () => Run(async () =>
        {
            await _app.Api.SaveNetworkAsync(_addSsid.Text, _addPass.Text);
            await _app.Api.ApplyNowAsync(_addSsid.Text);
            _msg.Show($"applying {_addSsid.Text}…", StatusBanner.Kind.Success);
            await Task.Delay(5000);
            _status = await _app.Api.WifiStatusAsync();
            RefreshStatus();
        }));
        var applyBoot = Ui.GhostButton("Save for next boot", () => Run(async () =>
        {
            await _app.Api.SaveNetworkAsync(_addSsid.Text, _addPass.Text);
            await _app.Api.ApplyBootAsync(_addSsid.Text);
            _msg.Show($"saved {_addSsid.Text} for boot", StatusBanner.Kind.Success);
        }));
        applyNow.IsEnabled = false;
        applyBoot.IsEnabled = false;
        _addSsid.TextChanged += () =>
        {
            var has = _addSsid.Text.Length > 0;
            applyNow.IsEnabled = has;
            applyBoot.IsEnabled = has;
        };
        var addButtons = Ui.HStack(Palette.S2, applyNow, applyBoot);
        var addPanel = new PanelCard("Add / Update Network", IconGlyphs.Add, _addSsid, _addPass, addButtons);

        var stack = Ui.VStack(Palette.S3, statusPanel, scanPanel, savedPanel, addPanel, _msg);
        stack.MaxWidth = 640;
        stack.HorizontalAlignment = HorizontalAlignment.Center;
        stack.Width = 640;

        var host = new Grid { Padding = new Thickness(Palette.S4) };
        host.Children.Add(stack);
        var scroll = new ScrollViewer { Content = host, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        Children.Add(scroll);

        RefreshStatus();

        // Автообновление статуса каждые 15 с (порт refreshStatusLoop).
        _statusTimer = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread().CreateTimer();
        _statusTimer.Interval = TimeSpan.FromSeconds(15);
        _statusTimer.Tick += (_, _) => _ = RefreshStatusAsync();
        _statusTimer.Start();
        Unloaded += (_, _) => _statusTimer.Stop();

        _ = RefreshStatusAsync();
        Run(async () =>
        {
            var saved = await _app.Api.SavedNetworksAsync();
            RefreshSaved(saved);
        });
    }

    private async Task RefreshStatusAsync()
    {
        try
        {
            _status = await _app.Api.WifiStatusAsync();
        }
        catch { return; }
        RefreshStatus();
    }

    // MARK: - Status panel

    private void RefreshStatus()
    {
        _statusRows.Children.Clear();
        if (_status is not DroneApi.WifiStatus s)
        {
            _statusRows.Children.Add(Ui.Text("loading…", Fonts.MonoSmall, Palette.Muted));
            return;
        }
        var mode = new ReadoutRow("Mode", s.Mode == "client" ? Palette.Ok : Palette.Warn);
        mode.Set(s.Mode.ToUpperInvariant(), s.Mode == "client" ? Palette.Ok : Palette.Warn);
        var net = new ReadoutRow("Network");
        net.Set(s.Ssid);
        var ip = new ReadoutRow("IP");
        ip.Set(s.Ip);
        var signal = new LabeledBarRow("Signal",
            s.Signal > 60 ? Palette.Ok : (s.Signal > 30 ? Palette.Warn : Palette.Danger));
        signal.Set($"{s.Signal}%", s.Signal);

        var refresh = Ui.GhostButton("Refresh", () => _ = RefreshStatusAsync(), IconGlyphs.Refresh);
        var switchMode = Ui.AccentButton("Switch Mode", () => _ = ConfirmSwitchModeAsync(s.Mode == "client" ? "hotspot" : "client"));
        var buttons = Ui.HStack(Palette.S2, refresh, switchMode);

        _statusRows.Children.Add(mode);
        _statusRows.Children.Add(net);
        _statusRows.Children.Add(ip);
        _statusRows.Children.Add(signal);
        _statusRows.Children.Add(buttons);
    }

    private async Task ConfirmSwitchModeAsync(string mode)
    {
        var dlg = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "Switch WiFi mode?",
            Content = mode == "hotspot"
                ? "The drone will broadcast its own hotspot; this PC will disconnect."
                : "The hotspot drops and the drone reconnects to wifi (~60 s).",
            PrimaryButtonText = $"Switch to {mode}",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
            RequestedTheme = ElementTheme.Dark,
        };
        ContentDialogResult result;
        try { result = await dlg.ShowAsync(); } catch { return; }
        if (result != ContentDialogResult.Primary) return;
        Run(async () =>
        {
            await _app.Api.WifiSetModeAsync(mode);
            _msg.Show($"switching to {mode}…", StatusBanner.Kind.Success);
        });
    }

    // MARK: - Scan panel

    private void DoScan()
    {
        if (_scanning) return;
        _scanning = true;
        _scanRing.Visibility = Visibility.Visible;
        Run(async () =>
        {
            try
            {
                var results = await _app.Api.WifiScanAsync();
                RefreshScan(results);
            }
            finally
            {
                _scanning = false;
                _scanRing.Visibility = Visibility.Collapsed;
            }
        });
    }

    private void RefreshScan(List<DroneApi.ScanNet> results)
    {
        _scanRows.Children.Clear();
        foreach (var n in results)
        {
            var dot = new Microsoft.UI.Xaml.Shapes.Ellipse
            {
                Width = 7, Height = 7,
                Fill = Palette.Brush(n.InUse ? Palette.Ok : Palette.Muted),
                VerticalAlignment = VerticalAlignment.Center,
            };
            var left = Ui.HStack(Palette.S2, dot, Ui.Text(n.Ssid, Fonts.MonoSmall, Palette.Text));
            var sigColor = n.Signal > 60 ? Palette.Ok : (n.Signal > 30 ? Palette.Warn : Palette.Danger);
            var connect = Ui.GhostButton("Connect", () => _addSsid.Text = n.Ssid);
            var right = Ui.HStack(Palette.S2,
                Ui.Text($"{n.Signal}%", Fonts.MonoSmall, sigColor),
                BadgeFactory.Badge(n.Band + "G", BandColor(n.Band)),
                connect);
            _scanRows.Children.Add(Ui.SpaceBetween(left, right));
        }
    }

    // MARK: - Saved panel

    private void RefreshSaved(List<string> saved)
    {
        _savedRows.Children.Clear();
        if (saved.Count == 0)
        {
            _savedRows.Children.Add(Ui.Text("none", Fonts.MonoSmall, Palette.Muted));
            return;
        }
        foreach (var name in saved)
        {
            var remove = Ui.GhostButton("Remove", () => Run(async () =>
            {
                await _app.Api.RemoveNetworkAsync(name);
                var updated = await _app.Api.SavedNetworksAsync();
                RefreshSaved(updated);
            }));
            ((TextBlock)remove.Content).Foreground = Palette.Brush(Palette.Danger);
            _savedRows.Children.Add(Ui.SpaceBetween(Ui.Text(name, Fonts.MonoSmall, Palette.Text), remove));
        }
    }

    private static Color BandColor(string b) =>
        b == "5" ? Palette.Ok : (b == "6" ? Palette.Accent2 : Palette.Warn);

    private void Run(Func<Task> op)
    {
        _ = RunCore(op);
        async Task RunCore(Func<Task> f)
        {
            try { await f(); }
            catch (Exception ex) { _msg.Show($"error: {ex.Message}", StatusBanner.Kind.Error); }
        }
    }
}
