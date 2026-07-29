using System.Runtime.InteropServices;

namespace BumblebeeGcs.Services;

/// <summary>
/// Не давать дисплею засыпать, пока идёт живое видео с дрона
/// (порт ProcessInfo.beginActivity → SetThreadExecutionState).
/// Вызывать с одного и того же потока (UI).
/// </summary>
public static class KeepAwake
{
    private const uint EsContinuous = 0x80000000;
    private const uint EsSystemRequired = 0x00000001;
    private const uint EsDisplayRequired = 0x00000002;

    [DllImport("kernel32.dll")]
    private static extern uint SetThreadExecutionState(uint esFlags);

    public static void Begin() =>
        SetThreadExecutionState(EsContinuous | EsSystemRequired | EsDisplayRequired);

    public static void End() =>
        SetThreadExecutionState(EsContinuous);
}
