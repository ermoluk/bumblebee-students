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
using BumblebeeGcs.Services;
using BumblebeeGcs.Theme;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.UI;

namespace BumblebeeGcs.Views;

/// <summary>
/// One-tap настройка дрона через его WiFi-хотспот. Показывает текущую сеть ПК
/// (авто) + поле пароля (вводится один раз, запоминается в PasswordVault),
/// сканирует эфир на `Bumblebee-*` и по выбору запускает полный hand-off
/// с живым лоадером, пока дрон не вернётся онлайн. Порт ProvisioningView.swift.
/// </summary>
public sealed class ProvisioningDialog : ContentDialog
{
    private readonly AppState _app;
    private readonly WifiHandoff _handoff;
    private readonly Grid _body = new();
    private readonly PasswordBox _password = new();
    private readonly Action _onChanged;

    public ProvisioningDialog(AppState app)
    {
        _app = app;
        _handoff = app.Handoff;

        Background = ConnectPalette.Background();
        Foreground = Palette.Brush(ConnectPalette.Text);
        BorderBrush = Palette.Brush(ConnectPalette.Hairline);
        CornerRadius = new CornerRadius(12);
        Resources["ContentDialogMaxWidth"] = 640.0;
        Resources["ContentDialogMinWidth"] = 560.0;

        _password.PlaceholderText = "WiFi password";
        _password.FontSize = 14;
        _password.FontFamily = Fonts.MonoFamily;
        _password.BorderThickness = new Thickness(0);
        _password.Padding = new Thickness(0);
        _password.MinHeight = 0;
        _password.VerticalAlignment = VerticalAlignment.Center;
        foreach (var state in new[] { "", "PointerOver", "Focused" })
        {
            _password.Resources[$"TextControlBackground{state}"] = Palette.Brush(Colors.Transparent);
            _password.Resources[$"TextControlBorderBrush{state}"] = Palette.Brush(Colors.Transparent);
        }
        _password.Resources["TextControlForegroundFocused"] = Palette.Brush(ConnectPalette.Text);
        _password.Resources["TextControlForegroundPointerOver"] = Palette.Brush(ConnectPalette.Text);
        _password.Resources["TextControlPlaceholderForeground"] = Palette.Brush(ConnectPalette.Faint);
        _password.PasswordChanged += (_, _) => RefreshBody();

        var root = new Grid
        {
            Width = 520,
            Height = 480,
            RowSpacing = 20,
        };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        var headerLeft = Ui.VStack(4,
            Ui.Text("Set up a drone", new FontSpec(20, new Windows.UI.Text.FontWeight(700)), ConnectPalette.Text),
            Ui.Text("Over its WiFi hotspot — no cables, no router", Fonts.BodyMed with { Mono = true }, ConnectPalette.Muted));
        var closeText = Ui.Text("Close", Fonts.Body, ConnectPalette.Muted);
        var close = new Border { Child = closeText, Padding = new Thickness(6, 4, 6, 4) };
        Ui.OnHover(close, h => closeText.Foreground = Palette.Brush(h ? ConnectPalette.Text : ConnectPalette.Muted));
        Ui.OnTap(close, () =>
        {
            if (_handoff.IsBusy) return;
            _handoff.Reset();
            Hide();
        });
        var header = Ui.SpaceBetween(headerLeft, close);
        Grid.SetRow(header, 0);
        root.Children.Add(header);

        var divider = new Border { Height = 1, Background = Palette.Brush(ConnectPalette.Hairline) };
        Grid.SetRow(divider, 1);
        root.Children.Add(divider);

        Grid.SetRow(_body, 2);
        root.Children.Add(_body);

        Content = root;

        // Пока идёт hand-off, диалог нельзя закрыть (Esc / клик мимо).
        Closing += (_, e) => { if (_handoff.IsBusy) e.Cancel = true; };

        _onChanged = () =>
        {
            RefreshBody();
            if (_handoff.Phase == WifiHandoff.PhaseKind.Done && _handoff.PhaseArg is string host && host.Length > 0)
            {
                _app.Connect(host);
                _handoff.Reset();
                Hide();
            }
        };
        _handoff.Changed += _onChanged;
        Closed += (_, _) => _handoff.Changed -= _onChanged;

        Opened += (_, _) =>
        {
            _handoff.RefreshCurrentSsid();
            _password.Password = CredentialStore.Password(_handoff.CurrentSsid) ?? "";
            _ = _handoff.ScanHotspotsAsync();
        };
        RefreshBody();
    }

    private bool CanProvision =>
        _handoff.CurrentSsid.Length > 0 && _password.Password.Length > 0 && !_handoff.IsBusy;

    // MARK: - Content by phase

    private void RefreshBody()
    {
        _body.Children.Clear();
        if (_handoff.IsBusy && _handoff.Phase != WifiHandoff.PhaseKind.Scanning)
            _body.Children.Add(BusyView());
        else if (_handoff.Phase == WifiHandoff.PhaseKind.NeedLocationPermission)
            _body.Children.Add(PermissionView());
        else
            _body.Children.Add(FormView());
    }

    private UIElement BusyView()
    {
        var text = _handoff.Phase switch
        {
            WifiHandoff.PhaseKind.Scanning => "Scanning the air for drone hotspots…",
            WifiHandoff.PhaseKind.JoiningHotspot => $"Joining {_handoff.PhaseArg}…",
            WifiHandoff.PhaseKind.PushingCreds => "Sending your WiFi to the drone…",
            WifiHandoff.PhaseKind.WaitingForDrone => $"Waiting for the drone to join {_handoff.CurrentSsid} and come online…",
            _ => "Working…",
        };
        var t1 = Ui.Text(text, new FontSpec(14, new Windows.UI.Text.FontWeight(600)), ConnectPalette.Text);
        t1.TextWrapping = TextWrapping.Wrap;
        t1.TextAlignment = TextAlignment.Center;
        t1.HorizontalAlignment = HorizontalAlignment.Center;
        var t2 = Ui.Text("Keep this window open — the PC will switch networks and come back on its own.",
            new FontSpec(11.5, new Windows.UI.Text.FontWeight(400), Mono: true), ConnectPalette.Muted);
        t2.TextWrapping = TextWrapping.Wrap;
        t2.TextAlignment = TextAlignment.Center;
        t2.HorizontalAlignment = HorizontalAlignment.Center;

        var ring = new ProgressRing { IsActive = true, Width = 44, Height = 44, HorizontalAlignment = HorizontalAlignment.Center };
        var stack = Ui.VStack(18, ring, t1, t2);
        stack.VerticalAlignment = VerticalAlignment.Center;
        stack.HorizontalAlignment = HorizontalAlignment.Stretch;
        return stack;
    }

    private UIElement PermissionView()
    {
        var icon = Ui.Icon(IconGlyphs.LocationOff, 34, ConnectPalette.Orange);
        icon.HorizontalAlignment = HorizontalAlignment.Center;
        var t1 = Ui.Text("Location access needed", Fonts.Title, ConnectPalette.Text);
        t1.HorizontalAlignment = HorizontalAlignment.Center;
        var msg = _handoff.LocationBlocked
            ? "Windows blocked Location for apps, so WiFi networks can't be read. Enable it in Settings ▸ Privacy & security ▸ Location, then Rescan."
            : "Windows needs Location access to read nearby WiFi. Allow it in Settings if scanning stays empty.";
        var t2 = Ui.Text(msg, Fonts.BodyMed with { Mono = true }, ConnectPalette.Muted);
        t2.TextWrapping = TextWrapping.Wrap;
        t2.TextAlignment = TextAlignment.Center;

        var openBtn = Ui.Text("Open Windows Settings", Fonts.Button, ConnectPalette.Orange);
        var open = new Border { Child = openBtn, Padding = new Thickness(6, 4, 6, 4) };
        Ui.OnTap(open, () => _ = Windows.System.Launcher.LaunchUriAsync(new Uri("ms-settings:privacy-location")));
        var rescanBtn = Ui.Text("Rescan", Fonts.Button, ConnectPalette.BlueSoft);
        var rescanB = new Border { Child = rescanBtn, Padding = new Thickness(6, 4, 6, 4) };
        Ui.OnTap(rescanB, () => _ = _handoff.ScanHotspotsAsync());
        var buttons = Ui.HStack(10, open, rescanB);
        buttons.HorizontalAlignment = HorizontalAlignment.Center;

        var stack = Ui.VStack(14, icon, t1, t2, buttons);
        stack.VerticalAlignment = VerticalAlignment.Center;
        return stack;
    }

    private UIElement FormView()
    {
        var stack = new StackPanel { Spacing = 16 };

        // Сеть (авто) + пароль (вводится один раз).
        var netStack = new StackPanel { Spacing = 8 };
        netStack.Children.Add(LabeledRow("YOUR WIFI",
            _handoff.CurrentSsid.Length == 0 ? "— not connected —" : _handoff.CurrentSsid));

        var pwdLabel = Ui.Text("PWD", Fonts.Label with { Mono = true }, ConnectPalette.Faint, tracking: 1.3);
        pwdLabel.Width = 42;
        var pwdRow = new Grid { ColumnSpacing = 8 };
        pwdRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        pwdRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        Grid.SetColumn(pwdLabel, 0);
        if (_password.Parent is Grid oldParent) oldParent.Children.Remove(_password);
        Grid.SetColumn(_password, 1);
        pwdRow.Children.Add(pwdLabel);
        pwdRow.Children.Add(_password);
        netStack.Children.Add(new Border
        {
            Background = Palette.Brush(ConnectPalette.RowBg),
            BorderBrush = Palette.Brush(ConnectPalette.Hairline),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(10),
            Padding = new Thickness(14, 10, 14, 10),
            Child = pwdRow,
        });
        var hint = Ui.Text("The drone will join this network. Entered once, remembered on this PC.",
            new FontSpec(10.5, new Windows.UI.Text.FontWeight(400), Mono: true), ConnectPalette.Faint);
        hint.TextWrapping = TextWrapping.Wrap;
        netStack.Children.Add(hint);
        stack.Children.Add(netStack);

        if (_handoff.Phase == WifiHandoff.PhaseKind.Failed && _handoff.PhaseArg.Length > 0)
        {
            var err = Ui.Text(_handoff.PhaseArg, Fonts.BodyMed, ConnectPalette.Orange);
            err.TextWrapping = TextWrapping.Wrap;
            stack.Children.Add(err);
        }

        // Список хотспотов.
        var listHeader = Ui.SpaceBetween(
            Ui.Text("DRONE HOTSPOTS", Fonts.Label with { Mono = true }, ConnectPalette.Faint, tracking: 1.2),
            RescanLink());
        stack.Children.Add(listHeader);

        if (_handoff.Phase == WifiHandoff.PhaseKind.Scanning)
        {
            var busy = Ui.HStack(8,
                new ProgressRing { IsActive = true, Width = 14, Height = 14 },
                Ui.Text("Scanning the air…", Fonts.BodyMed with { Mono = true }, ConnectPalette.Muted));
            stack.Children.Add(busy);
        }
        else if (_handoff.Hotspots.Count == 0)
        {
            var none = Ui.Text(
                "No drone hotspots nearby. Power on a drone with no known WiFi — it raises a Bumblebee-XXXX hotspot — then Rescan.",
                Fonts.BodyMed with { Mono = true }, ConnectPalette.Muted);
            none.TextWrapping = TextWrapping.Wrap;
            stack.Children.Add(none);
        }
        else
        {
            var list = new StackPanel { Spacing = 8 };
            foreach (var h in _handoff.Hotspots) list.Children.Add(HotspotRow(h));
            stack.Children.Add(new ScrollViewer { Content = list, MaxHeight = 190 });
        }
        return stack;
    }

    private UIElement RescanLink()
    {
        var t = Ui.Text("Rescan", Fonts.ButtonSm with { Weight = new Windows.UI.Text.FontWeight(600) }, ConnectPalette.BlueSoft);
        var b = new Border { Child = t, Padding = new Thickness(4, 2, 4, 2) };
        Ui.OnTap(b, () => _ = _handoff.ScanHotspotsAsync());
        return b;
    }

    private UIElement HotspotRow(WifiHandoff.Hotspot h)
    {
        var left = Ui.HStack(12,
            Ui.Icon(IconGlyphs.Wifi, 13, ConnectPalette.Orange),
            Ui.Text(h.Ssid, new FontSpec(14, new Windows.UI.Text.FontWeight(600)), ConnectPalette.Text));
        var right = Ui.HStack(10,
            Ui.Text($"{h.Rssi} dBm", Fonts.Label with { Mono = true }, ConnectPalette.Muted2),
            Ui.Text("Set up →", Fonts.Button, CanProvision ? ConnectPalette.Orange : ConnectPalette.Faint));
        var content = Ui.SpaceBetween(left, right, 8);
        content.Margin = new Thickness(14, 12, 14, 12);

        return new Controls.HoverRow(content, 11,
            ConnectPalette.RowBg, Palette.WithAlpha(ConnectPalette.Orange, 0.06),
            ConnectPalette.Hairline, Palette.WithAlpha(ConnectPalette.Orange, 0.5),
            onTap: () =>
            {
                if (!CanProvision) return;
                CredentialStore.SetPassword(_password.Password, _handoff.CurrentSsid);
                _ = _handoff.ProvisionAsync(h.Ssid, _handoff.CurrentSsid, _password.Password, _ => { });
            });
    }

    private static UIElement LabeledRow(string label, string value)
    {
        var l = Ui.Text(label, Fonts.Label with { Mono = true }, ConnectPalette.Faint, tracking: 1.3);
        l.Width = 72;
        var row = Ui.HStack(8, l, Ui.Text(value, new FontSpec(14, new Windows.UI.Text.FontWeight(600)), ConnectPalette.Text));
        return new Border
        {
            Background = Palette.Brush(ConnectPalette.RowBg),
            BorderBrush = Palette.Brush(ConnectPalette.Hairline),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(10),
            Padding = new Thickness(14, 10, 14, 10),
            Child = row,
        };
    }
}
