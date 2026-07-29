// SimDrone — мок дрона Bumblebee на localhost для end-to-end проверки GCS.
// Порты: rosbridge WS :9090, метрики :8888, API :8765, MJPEG :8080.
// HttpListener с префиксами localhost не требует прав администратора,
// поэтому в приложении подключаться нужно к хосту "localhost".

using System.Collections.Concurrent;
using System.Drawing;
using System.Drawing.Imaging;
using System.Net;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

var sim = new SimState();
Console.WriteLine("SimDrone: connect the GCS to host \"localhost\"");
_ = Task.Run(() => RosbridgeServer(sim));
_ = Task.Run(() => JsonServer(8888, MetricsJson));
_ = Task.Run(() => ApiServer(sim));
_ = Task.Run(() => MjpegServer(sim));

var start = DateTime.UtcNow;
while (true)
{
    sim.Tick((DateTime.UtcNow - start).TotalSeconds);
    await Task.Delay(50); // 20 Hz
}

// ---------------------------------------------------------------- rosbridge

static async Task RosbridgeServer(SimState sim)
{
    var listener = new HttpListener();
    listener.Prefixes.Add("http://localhost:9090/");
    listener.Start();
    Console.WriteLine("[9090] rosbridge ws up");
    while (true)
    {
        var ctx = await listener.GetContextAsync();
        if (!ctx.Request.IsWebSocketRequest)
        {
            ctx.Response.StatusCode = 200; // TCP-проба скана считает порт открытым
            ctx.Response.Close();
            continue;
        }
        _ = Task.Run(async () =>
        {
            var ws = (await ctx.AcceptWebSocketAsync(null)).WebSocket;
            Console.WriteLine("[9090] client connected");
            var topics = new ConcurrentDictionary<string, bool>();
            _ = Task.Run(async () =>
            {
                var buf = new byte[16384];
                try
                {
                    while (ws.State == WebSocketState.Open)
                    {
                        var r = await ws.ReceiveAsync(buf, CancellationToken.None);
                        if (r.MessageType == WebSocketMessageType.Close) break;
                        var doc = JsonDocument.Parse(new ReadOnlyMemory<byte>(buf, 0, r.Count));
                        if (doc.RootElement.TryGetProperty("op", out var op) && op.GetString() == "subscribe" &&
                            doc.RootElement.TryGetProperty("topic", out var t) && t.GetString() is string topic)
                        {
                            topics[topic] = true;
                            Console.WriteLine($"[9090] subscribe {topic}");
                        }
                    }
                }
                catch { }
            });
            try
            {
                var lastStatus = DateTime.UtcNow;
                while (ws.State == WebSocketState.Open)
                {
                    foreach (var (topic, payload) in sim.Publications())
                    {
                        if (!topics.ContainsKey(topic)) continue;
                        var msg = JsonSerializer.Serialize(new Dictionary<string, object?>
                        {
                            ["op"] = "publish",
                            ["topic"] = topic,
                            ["msg"] = payload,
                        });
                        await ws.SendAsync(Encoding.UTF8.GetBytes(msg), WebSocketMessageType.Text, true, CancellationToken.None);
                    }
                    if ((DateTime.UtcNow - lastStatus).TotalSeconds > 12)
                    {
                        lastStatus = DateTime.UtcNow;
                        var msg = JsonSerializer.Serialize(new
                        {
                            op = "publish",
                            topic = "/mavros/statustext/recv",
                            msg = new { severity = 2, text = $"SIM checkpoint at {DateTime.Now:HH:mm:ss}" },
                        });
                        await ws.SendAsync(Encoding.UTF8.GetBytes(msg), WebSocketMessageType.Text, true, CancellationToken.None);
                    }
                    await Task.Delay(66); // ~15 Hz
                }
            }
            catch { }
            Console.WriteLine("[9090] client dropped");
        });
    }
}

// ---------------------------------------------------------------- metrics :8888

static string MetricsJson()
{
    var rnd = Random.Shared;
    return JsonSerializer.Serialize(new
    {
        hostname = "sim-drone",
        cpu_temp = 52 + rnd.NextDouble() * 12,
        cpu_pct = 25 + rnd.NextDouble() * 40,
        load1 = 0.8 + rnd.NextDouble(),
        load5 = 0.9,
        load15 = 0.7,
        cpu_count = 4,
        mem_used = 1400 + rnd.Next(0, 300),
        mem_total = 3924,
        mem_pct = 40 + rnd.NextDouble() * 15,
    });
}

static async Task JsonServer(int port, Func<string> body)
{
    var listener = new HttpListener();
    listener.Prefixes.Add($"http://localhost:{port}/");
    listener.Start();
    Console.WriteLine($"[{port}] json up");
    while (true)
    {
        var ctx = await listener.GetContextAsync();
        var data = Encoding.UTF8.GetBytes(body());
        ctx.Response.ContentType = "application/json";
        await ctx.Response.OutputStream.WriteAsync(data);
        ctx.Response.Close();
    }
}

// ---------------------------------------------------------------- API :8765

static async Task ApiServer(SimState sim)
{
    var listener = new HttpListener();
    listener.Prefixes.Add("http://localhost:8765/");
    listener.Start();
    Console.WriteLine("[8765] api up");
    while (true)
    {
        var ctx = await listener.GetContextAsync();
        var path = ctx.Request.Url?.AbsolutePath ?? "/";
        string reqBody = "";
        if (ctx.Request.HasEntityBody)
            using (var r = new StreamReader(ctx.Request.InputStream))
                reqBody = await r.ReadToEndAsync();
        Console.WriteLine($"[8765] {ctx.Request.HttpMethod} {path} {reqBody}");

        object response = path switch
        {
            "/api/wifi/status" => new { mode = "client", ssid = "SimNet-5G", ip = "127.0.0.1", signal = 78 },
            "/api/wifi/scan" => new object[]
            {
                new { ssid = "SimNet-5G", signal = 78, in_use = true, band = "5", freq = 5300 },
                new { ssid = "HomeWifi", signal = 55, in_use = false, band = "2.4", freq = 2412 },
                new { ssid = "Neighbor6E", signal = 23, in_use = false, band = "6", freq = 5955 },
            },
            "/api/wifi/networks" => new object[] { new { name = "SimNet-5G" }, new { name = "FieldRouter" } },
            "/api/sounds/tts" => new { tune = "MFT180L8O5CDEFG", phonemes = "k-o-t" },
            "/api/sounds/play" => new { ok = true },
            _ => new { ok = true },
        };
        var data = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(response));
        ctx.Response.ContentType = "application/json";
        await ctx.Response.OutputStream.WriteAsync(data);
        ctx.Response.Close();
    }
}

// ---------------------------------------------------------------- MJPEG :8080

static async Task MjpegServer(SimState sim)
{
    var listener = new HttpListener();
    listener.Prefixes.Add("http://localhost:8080/");
    listener.Start();
    Console.WriteLine("[8080] mjpeg up");
    while (true)
    {
        var ctx = await listener.GetContextAsync();
        var topic = ctx.Request.QueryString["topic"] ?? "?";
        Console.WriteLine($"[8080] stream start {topic}");
        _ = Task.Run(async () =>
        {
            var resp = ctx.Response;
            resp.ContentType = "multipart/x-mixed-replace; boundary=frame";
            // Без Content-Length HttpListener требует chunked; HttpClient на
            // стороне GCS прозрачно раздекодирует chunked обратно в байты.
            resp.SendChunked = true;
            var stream = resp.OutputStream;
            try
            {
                var n = 0;
                while (true)
                {
                    var jpeg = RenderFrame(topic, n++, sim);
                    var header = Encoding.ASCII.GetBytes(
                        $"--frame\r\nContent-Type: image/jpeg\r\nContent-Length: {jpeg.Length}\r\n\r\n");
                    await stream.WriteAsync(header);
                    await stream.WriteAsync(jpeg);
                    await stream.WriteAsync(Encoding.ASCII.GetBytes("\r\n"));
                    await stream.FlushAsync();
                    await Task.Delay(83); // ~12 fps
                }
            }
            catch { Console.WriteLine($"[8080] stream end {topic}"); }
            try { resp.Close(); } catch { }
        });
    }
}

static byte[] RenderFrame(string topic, int n, SimState sim)
{
    using var bmp = new Bitmap(320, 240);
    using var g = Graphics.FromImage(bmp);
    var baseColor = topic.Contains("aruco") ? Color.FromArgb(30, 60, 30) : Color.FromArgb(25, 30, 45);
    g.Clear(baseColor);
    using (var pen = new Pen(Color.FromArgb(70, 90, 120)))
        for (var i = 0; i < 320; i += 40)
        {
            g.DrawLine(pen, i, 0, i, 240);
            if (i < 240) g.DrawLine(pen, 0, i, 320, i);
        }
    // «Дрон» — движущийся маркер.
    var cx = 160 + (float)(Math.Sin(n * 0.05) * 100);
    var cy = 120 + (float)(Math.Cos(n * 0.07) * 60);
    g.FillEllipse(Brushes.Orange, cx - 10, cy - 10, 20, 20);
    g.DrawString($"{topic}", new Font("Consolas", 9), Brushes.White, 4, 4);
    g.DrawString($"{DateTime.Now:HH:mm:ss.f}  z={sim.Z:F2}m", new Font("Consolas", 9), Brushes.White, 4, 222);
    using var ms = new MemoryStream();
    bmp.Save(ms, ImageFormat.Jpeg);
    return ms.ToArray();
}

// ---------------------------------------------------------------- состояние полёта

sealed class SimState
{
    double _t;
    public double X, Y, Z, Roll, Pitch, Yaw, Vx, Vy, Vz;
    public double Voltage = 25.2;
    public bool Armed;

    public void Tick(double t)
    {
        _t = t;
        X = 3 * Math.Cos(t * 0.3);
        Y = 3 * Math.Sin(t * 0.3);
        Z = 1.5 + 0.5 * Math.Sin(t * 0.15);
        Vx = -0.9 * Math.Sin(t * 0.3);
        Vy = 0.9 * Math.Cos(t * 0.3);
        Vz = 0.075 * Math.Cos(t * 0.15);
        Roll = 10 * Math.Sin(t * 0.5);
        Pitch = 8 * Math.Cos(t * 0.4);
        Yaw = (t * 12) % 360 - 180;
        Voltage = Math.Max(19.8, 25.2 - t * 0.01);
        Armed = (int)(t / 30) % 2 == 1;
    }

    static object Quat(double rollDeg, double pitchDeg, double yawDeg)
    {
        double r = rollDeg * Math.PI / 360, p = pitchDeg * Math.PI / 360, y = yawDeg * Math.PI / 360;
        double cr = Math.Cos(r), sr = Math.Sin(r), cp = Math.Cos(p), sp = Math.Sin(p), cy = Math.Cos(y), sy = Math.Sin(y);
        return new
        {
            w = cr * cp * cy + sr * sp * sy,
            x = sr * cp * cy - cr * sp * sy,
            y = cr * sp * cy + sr * cp * sy,
            z = cr * cp * sy - sr * sp * cy,
        };
    }

    public IEnumerable<(string Topic, object Msg)> Publications()
    {
        var pct = Math.Clamp((Voltage / 6 - 3.3) / (4.2 - 3.3), 0, 1);
        yield return ("/mavros/state", new { mode = Armed ? "OFFBOARD" : "STABILIZED", armed = Armed });
        yield return ("/mavros/battery", new { voltage = Voltage, percentage = pct });
        yield return ("/mavros/mavros/pose", new
        {
            pose = new { position = new { x = X, y = Y, z = Z }, orientation = Quat(Roll, Pitch, Yaw) },
        });
        yield return ("/mavros/mavros/velocity_local", new
        {
            twist = new { linear = new { x = Vx, y = Vy, z = Vz } },
        });
        yield return ("/mavros/mavros/data", new
        {
            angular_velocity = new
            {
                x = 0.08 * Math.Sin(_t * 2),
                y = 0.06 * Math.Cos(_t * 1.7),
                z = 0.21,
            },
            linear_acceleration = new
            {
                x = 0.4 * Math.Sin(_t),
                y = 0.3 * Math.Cos(_t * 1.2),
                z = 9.81 + 0.2 * Math.Sin(_t * 3),
            },
        });
    }
}
