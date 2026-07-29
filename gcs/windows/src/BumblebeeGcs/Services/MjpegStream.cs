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

namespace BumblebeeGcs.Services;

/// <summary>
/// Нативный MJPEG (multipart/x-mixed-replace) клиент. Стримит с
/// http://host:8080/stream?..., режет поток по JPEG SOI/EOI маркерам и отдаёт
/// последний полный кадр. Порт MJPEGStream.swift: при пачке кадров декодируется
/// только самый свежий; авто-ретрай через 1.2 с; лимит буфера 4 МБ.
/// </summary>
public sealed class MjpegStream
{
    /// <summary>Сырые байты JPEG последнего полного кадра (фоновый поток!).</summary>
    public event Action<byte[]>? FrameReady;
    public event Action<bool>? ReceivingChanged;

    private static readonly HttpClient Http = new() { Timeout = Timeout.InfiniteTimeSpan };

    private Uri? _currentUrl;
    private CancellationTokenSource? _cts;

    public void Start(Uri url)
    {
        if (url == _currentUrl && _cts is not null) return;
        Stop();
        _currentUrl = url;
        var cts = new CancellationTokenSource();
        _cts = cts;
        _ = RunAsync(url, cts.Token);
    }

    public void Stop()
    {
        _cts?.Cancel();
        _cts = null;
        _currentUrl = null;
        ReceivingChanged?.Invoke(false);
    }

    private async Task RunAsync(Uri url, CancellationToken ct)
    {
        var buffer = new FrameBuffer();
        var chunk = new byte[64 * 1024];
        while (!ct.IsCancellationRequested)
        {
            buffer.Clear();
            try
            {
                using var req = new HttpRequestMessage(HttpMethod.Get, url);
                using var resp = await Http.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, ct);
                await using var stream = await resp.Content.ReadAsStreamAsync(ct);
                int n;
                while ((n = await stream.ReadAsync(chunk, ct)) > 0)
                {
                    buffer.Append(chunk, n);
                    if (buffer.ExtractLastFrame() is byte[] frame)
                    {
                        FrameReady?.Invoke(frame);
                        ReceivingChanged?.Invoke(true);
                    }
                    // Страховка от бесконечного роста, если полный кадр не приходит.
                    if (buffer.Count > 4 * 1024 * 1024) buffer.Clear();
                }
            }
            catch when (ct.IsCancellationRequested) { return; }
            catch { /* сервер перезапускается / wifi моргнул */ }

            ReceivingChanged?.Invoke(false);
            try { await Task.Delay(1200, ct); } catch { return; }
        }
    }

    /// <summary>Растущий байтовый буфер с выделением последнего полного JPEG (SOI..EOI).</summary>
    private sealed class FrameBuffer
    {
        private byte[] _data = new byte[256 * 1024];
        private int _len;

        public int Count => _len;

        public void Clear() => _len = 0;

        public void Append(byte[] chunk, int n)
        {
            if (_len + n > _data.Length)
                Array.Resize(ref _data, Math.Max(_data.Length * 2, _len + n));
            Array.Copy(chunk, 0, _data, _len, n);
            _len += n;
        }

        /// <summary>
        /// Съедает все полные JPEG в буфере, возвращая только ПОСЛЕДНИЙ (свежайший).
        /// Мусор до SOI отбрасывается.
        /// </summary>
        public byte[]? ExtractLastFrame()
        {
            byte[]? last = null;
            var pos = 0;
            while (true)
            {
                var start = IndexOfMarker(pos, 0xFF, 0xD8);
                if (start < 0) break;
                var end = IndexOfMarker(start + 2, 0xFF, 0xD9);
                if (end < 0)
                {
                    // Полного кадра ещё нет — компактируем, отбросив мусор до SOI.
                    if (start > 0) Compact(start);
                    return last;
                }
                var frameLen = end + 2 - start;
                last = new byte[frameLen];
                Array.Copy(_data, start, last, 0, frameLen);
                pos = end + 2;
            }
            if (pos > 0) Compact(pos);
            return last;
        }

        private int IndexOfMarker(int from, byte a, byte b)
        {
            for (var i = Math.Max(0, from); i < _len - 1; i++)
                if (_data[i] == a && _data[i + 1] == b) return i;
            return -1;
        }

        private void Compact(int from)
        {
            Array.Copy(_data, from, _data, 0, _len - from);
            _len -= from;
        }
    }
}
