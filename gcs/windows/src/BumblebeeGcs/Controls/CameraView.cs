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
using System.Runtime.InteropServices.WindowsRuntime;
using BumblebeeGcs.Services;
using BumblebeeGcs.Theme;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage.Streams;
using Windows.UI;

namespace BumblebeeGcs.Controls;

/// <summary>
/// Нативная MJPEG-камера. Владеет MjpegStream, пересобирает URL при смене
/// хоста/топика. Поддерживает переворот на 180°. Порт CameraView.swift.
/// </summary>
public sealed class CameraView : Grid
{
    public string Host = "";
    public string Topic = "";
    public int Quality = 60, Fps = 12, StreamWidth = 320, StreamHeight = 240;

    private readonly MjpegStream _stream = new();
    private readonly Image _image;
    private readonly StackPanel _placeholder;
    private bool _flipped;
    private bool _decoding;
    private byte[]? _pendingFrame;
    private Uri? _startedUrl;

    public CameraView(bool showFlipButton = true)
    {
        Background = Palette.Brush(Colors.Black);

        _image = new Image
        {
            Stretch = Stretch.Uniform,
            RenderTransformOrigin = new Windows.Foundation.Point(0.5, 0.5),
        };
        Children.Add(_image);

        _placeholder = Ui.VStack(Palette.S2,
            new ProgressRing { IsActive = true, Width = 20, Height = 20 },
            Ui.Text("waiting for video…", Fonts.MonoSmall, Palette.Muted));
        _placeholder.HorizontalAlignment = HorizontalAlignment.Center;
        _placeholder.VerticalAlignment = VerticalAlignment.Center;
        ((FrameworkElement)_placeholder.Children[1]).HorizontalAlignment = HorizontalAlignment.Center;
        Children.Add(_placeholder);

        if (showFlipButton)
        {
            var flip = Ui.OverlayIconButton(IconGlyphs.Flip, "Flip 180°", () =>
            {
                _flipped = !_flipped;
                _image.RenderTransform = _flipped ? new RotateTransform { Angle = 180 } : null;
            });
            flip.HorizontalAlignment = HorizontalAlignment.Right;
            flip.VerticalAlignment = VerticalAlignment.Top;
            flip.Margin = new Thickness(Palette.S1 + 2);
            Children.Add(flip);
        }

        var dq = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread();
        _stream.FrameReady += bytes => dq.TryEnqueue(() => OnFrame(bytes));

        Loaded += (_, _) => Restart();
        Unloaded += (_, _) => { _stream.Stop(); _startedUrl = null; };
    }

    private Uri? StreamUrl =>
        Uri.TryCreate($"http://{Host}:8080/stream?topic={Topic}&type=mjpeg&quality={Quality}&fps={Fps}&width={StreamWidth}&height={StreamHeight}",
            UriKind.Absolute, out var u) ? u : null;

    public void Restart()
    {
        if (StreamUrl is not Uri url || string.IsNullOrEmpty(Host)) return;
        if (_startedUrl == url) return;
        _startedUrl = url;
        _image.Source = null;
        _placeholder.Visibility = Visibility.Visible;
        _stream.Start(url);
    }

    public void SetTopic(string topic)
    {
        if (Topic == topic) return;
        Topic = topic;
        Restart();
    }

    /// <summary>Декодируем только свежайший кадр: если декодер занят — кадр ждёт (и замещается).</summary>
    private async void OnFrame(byte[] jpeg)
    {
        if (_decoding)
        {
            _pendingFrame = jpeg;
            return;
        }
        _decoding = true;
        try
        {
            while (true)
            {
                using var ms = new InMemoryRandomAccessStream();
                await ms.WriteAsync(jpeg.AsBuffer());
                ms.Seek(0);
                var bmp = new BitmapImage();
                await bmp.SetSourceAsync(ms);
                _image.Source = bmp;
                _placeholder.Visibility = Visibility.Collapsed;
                if (_pendingFrame is null) break;
                jpeg = _pendingFrame;
                _pendingFrame = null;
            }
        }
        catch { /* битый кадр — ждём следующий */ }
        finally { _decoding = false; }
    }
}
