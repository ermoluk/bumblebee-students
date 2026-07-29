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

/// <summary>LED, зуммер и TTS. Порт EntertainmentView.swift.</summary>
public sealed class EntertainmentPage : Grid
{
    private enum LedKind { Color, Anim, None }

    private readonly AppState _app;

    private Color _color = Colors.White;
    private string? _activeAnim;
    private bool _isOn = true;
    private (LedKind Kind, Color Color, string Anim) _lastState = (LedKind.Color, Colors.White, "");
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer _colorDebounce;

    private readonly TextBlock _hexLabel;
    private readonly Button _onOffBtn;
    private readonly List<(string Name, ChipButton Chip)> _animChips = new();
    private readonly GlassTextField _customTune;
    private readonly SegmentedTabs _fmtTabs;
    private readonly Button _playBtn;
    private readonly StatusBanner _soundBanner = new();
    private readonly GlassTextField _ttsText;
    private readonly SegmentedTabs _langTabs;
    private readonly Button _speakBtn;
    private readonly StatusBanner _ttsBanner = new();

    private static readonly string[] Animations = { "breathing", "rainbow", "police", "strobe", "fire", "theater" };

    private static readonly (string Name, string Tune, string Fmt)[] Presets =
    {
        ("beep", "MFT100L16O5C", "QBASIC"),
        ("ok", "MFT180L8O5CEG", "QBASIC"),
        ("error", "MFT180L8O5GEC<G", "QBASIC"),
        ("notify", "MFT180L8O5E4C4", "QBASIC"),
        ("arming", "MFT180L8O4G4O5C4", "QBASIC"),
        ("imperial", "MFT120L4O4GGGL8E<L16B>L4GL8E<L16B>L2G", "QBASIC"),
        ("mario", "MFT200L8O5EEP8EP8CEP8GP8P4<GP4", "QBASIC"),
        ("tetris", "MFT160L4O5EL8BL8>CL4DL8>CL8<BL4AL8AL8>CL4EL8DL8>C", "QBASIC"),
    };

    private static readonly string[] Languages = { "en", "ru", "de", "fr", "es" };

    public EntertainmentPage(AppState app)
    {
        _app = app;

        // MARK: LED panel
        var picker = new ColorPicker
        {
            IsAlphaEnabled = false,
            Color = Colors.White,
            IsColorChannelTextInputVisible = false,
            IsHexInputVisible = false,
            IsColorSliderVisible = true,
            IsColorPreviewVisible = false,
            Width = 260,
            HorizontalAlignment = HorizontalAlignment.Left,
        };
        _colorDebounce = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread().CreateTimer();
        _colorDebounce.Interval = TimeSpan.FromMilliseconds(120);
        _colorDebounce.IsRepeating = false;
        _colorDebounce.Tick += (_, _) =>
        {
            var (r, g, b) = Rgb;
            Run(async () =>
            {
                await _app.Api.LedColorAsync(r, g, b);
                _activeAnim = null;
                RefreshAnimChips();
                _lastState = (LedKind.Color, _color, "");
                _isOn = true;
                RefreshOnOff();
            });
        };
        picker.ColorChanged += (_, e) =>
        {
            _color = e.NewColor;
            _hexLabel!.Text = HexString;
            _colorDebounce.Stop();
            _colorDebounce.Start();
        };

        _hexLabel = Ui.Text("#FFFFFF", Fonts.Mono, Palette.Muted);
        _onOffBtn = Ui.GhostButton("Off", ToggleOnOff);
        var resetBtn = Ui.GhostButton("Reset", () => Run(async () =>
        {
            await _app.Api.LedResetAsync();
            _activeAnim = null;
            RefreshAnimChips();
            _lastState = (LedKind.None, default, "");
        }));
        var ledRow = Ui.SpaceBetween(_hexLabel, Ui.HStack(Palette.S2, _onOffBtn, resetBtn));
        var ledPanel = new PanelCard("LED Color", IconGlyphs.LedColor, picker, ledRow);

        // MARK: Animations panel
        var animGrid = new AdaptiveGridPanel { MinItemWidth = 90, Spacing = Palette.S2 };
        foreach (var name in Animations)
        {
            var chip = new ChipButton(Capitalize(name), false, () => Run(async () =>
            {
                await _app.Api.LedAnimationAsync(name);
                _activeAnim = name;
                RefreshAnimChips();
                _lastState = (LedKind.Anim, default, name);
                _isOn = true;
                RefreshOnOff();
            }), fullWidth: true);
            _animChips.Add((name, chip));
            animGrid.Children.Add(chip);
        }
        var animPanel = new PanelCard("Animations", IconGlyphs.Sparkles, animGrid);

        // MARK: Buzzer panel
        var presetGrid = new AdaptiveGridPanel { MinItemWidth = 80, Spacing = Palette.S2 };
        foreach (var (name, tune, fmt) in Presets)
        {
            var b = Ui.GhostButton(name, () => Run(async () =>
            {
                await _app.Api.PlayTuneAsync(tune, fmt);
                _soundBanner.Show($"played {name}", StatusBanner.Kind.Success);
            }));
            b.HorizontalAlignment = HorizontalAlignment.Stretch;
            b.HorizontalContentAlignment = HorizontalAlignment.Center;
            presetGrid.Children.Add(b);
        }
        _customTune = new GlassTextField("Custom tune");
        _fmtTabs = new SegmentedTabs(new[] { ("QBASIC", "QBASIC"), ("MML", "MML") }, "QBASIC");
        _playBtn = Ui.AccentButton("Play Tune", () => Run(async () =>
        {
            var r = await _app.Api.PlayTuneAsync(_customTune.Text, _fmtTabs.Selection);
            _soundBanner.Show(DroneApi.Str(r, "error") ?? "played",
                DroneApi.Str(r, "error") is null ? StatusBanner.Kind.Success : StatusBanner.Kind.Error);
        }));
        _playBtn.IsEnabled = false;
        _customTune.TextChanged += () => _playBtn.IsEnabled = _customTune.Text.Length > 0;
        var playRow = Ui.HStack(Palette.S2, _fmtTabs, _playBtn);
        var soundsPanel = new PanelCard("Buzzer", IconGlyphs.Speaker, presetGrid, _customTune, playRow, _soundBanner);

        // MARK: TTS panel
        _ttsText = new GlassTextField("Text to speak");
        _langTabs = new SegmentedTabs(Languages.Select(l => (l.ToUpperInvariant(), l)), "en");
        _speakBtn = Ui.AccentButton("Speak", () => Run(async () =>
        {
            var r = await _app.Api.TtsAsync(_ttsText.Text, _langTabs.Selection);
            var tune = DroneApi.Str(r, "tune") ?? "";
            var ph = DroneApi.Str(r, "phonemes") is string s ? $" · {s}" : "";
            var outText = tune + ph;
            _ttsBanner.Show(outText.Length > 230 ? outText[..230] : outText, StatusBanner.Kind.Info);
        }));
        _speakBtn.IsEnabled = false;
        _ttsText.TextChanged += () => _speakBtn.IsEnabled = _ttsText.Text.Length > 0;
        var ttsPanel = new PanelCard("Speech (TTS)", IconGlyphs.Tts, _ttsText, _langTabs, _speakBtn);
        ttsPanel.Add(_ttsBanner);

        // MARK: Layout
        var grid = new AdaptiveGridPanel { MinItemWidth = 320, Spacing = Palette.S4, MaxWidth = 980 };
        grid.Children.Add(ledPanel);
        grid.Children.Add(animPanel);
        grid.Children.Add(soundsPanel);
        grid.Children.Add(ttsPanel);
        grid.HorizontalAlignment = HorizontalAlignment.Center;

        var host = new Grid { Padding = new Thickness(Palette.S4) };
        host.Children.Add(grid);
        var scroll = new ScrollViewer { Content = host, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        Children.Add(scroll);

        Unloaded += (_, _) => _colorDebounce.Stop();
    }

    // MARK: - Helpers

    private (int R, int G, int B) Rgb => (_color.R, _color.G, _color.B);
    private string HexString => $"#{_color.R:X2}{_color.G:X2}{_color.B:X2}";

    private static string Capitalize(string s) => s.Length == 0 ? s : char.ToUpperInvariant(s[0]) + s[1..];

    private void RefreshAnimChips()
    {
        foreach (var (name, chip) in _animChips) chip.SetSelected(name == _activeAnim);
    }

    private void RefreshOnOff() =>
        ((TextBlock)_onOffBtn.Content).Text = _isOn ? "Off" : "On";

    private void ToggleOnOff()
    {
        if (_isOn)
        {
            Run(async () =>
            {
                await _app.Api.LedColorAsync(0, 0, 0);
                _isOn = false;
                RefreshOnOff();
            });
        }
        else
        {
            _isOn = true;
            RefreshOnOff();
            var (kind, color, anim) = _lastState;
            Run(async () =>
            {
                switch (kind)
                {
                    case LedKind.Anim: await _app.Api.LedAnimationAsync(anim); break;
                    case LedKind.Color: await _app.Api.LedColorAsync(color.R, color.G, color.B); break;
                    default: await _app.Api.LedResetAsync(); break;
                }
            });
        }
    }

    private void Run(Func<Task> op)
    {
        _ = RunCore(op);
        async Task RunCore(Func<Task> f)
        {
            try { await f(); }
            catch (Exception ex) { _soundBanner.Show($"error: {ex.Message}", StatusBanner.Kind.Error); }
        }
    }
}
