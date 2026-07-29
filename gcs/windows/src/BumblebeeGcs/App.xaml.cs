using BumblebeeGcs.Services;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;

namespace BumblebeeGcs;

public partial class App : Application
{
    public static AppState State { get; private set; } = null!;
    public static MainWindow? Window { get; private set; }

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        State = new AppState(DispatcherQueue.GetForCurrentThread());
        State.Scanner.StartDiscovery();       // непрерывный DNS-SD
        State.Scanner.Scan();                 // разовый субнет-фолбэк
        _ = State.Handoff.RequestLocationAsync(); // выяснить разрешение на WiFi-скан заранее

        Window = new MainWindow();
        Window.Activate();

        // Тестовый хук: BumblebeeGcs.exe --connect <host> подключается сразу
        // (используется для end-to-end прогонов с SimDrone).
        var cli = Environment.GetCommandLineArgs();
        var idx = Array.IndexOf(cli, "--connect");
        if (idx >= 0 && idx + 1 < cli.Length)
            State.Connect(cli[idx + 1]);
    }
}
