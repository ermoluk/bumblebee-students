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
