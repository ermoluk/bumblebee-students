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
using BumblebeeGcs.Theme;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;

namespace BumblebeeGcs.Views;

/// <summary>
/// Boot-экран — статичный бренд-холд перед экраном подключения.
/// Без свечения и анимаций: только знак и словомарка на connect-палитре.
/// </summary>
public sealed class SplashView : Grid
{
    public SplashView()
    {
        Background = ConnectPalette.Background();

        var title = new TextBlock
        {
            FontSize = 26,
            FontWeight = new Windows.UI.Text.FontWeight(700),
            FontFamily = Fonts.UiFamily,
            CharacterSpacing = -12, // tracking -0.3 @ 26pt
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        title.Inlines.Add(new Run { Text = "Bumblebee ", Foreground = Palette.Brush(ConnectPalette.Text) });
        title.Inlines.Add(new Run { Text = "GCS", Foreground = Palette.Brush(ConnectPalette.Orange) });

        var subtitle = Ui.Text("GROUND CONTROL STATION", Fonts.Label with { Mono = true }, ConnectPalette.Muted, tracking: 2);
        subtitle.HorizontalAlignment = HorizontalAlignment.Center;

        var logo = Ui.AppLogo(76, 18);
        logo.HorizontalAlignment = HorizontalAlignment.Center;

        var stack = Ui.VStack(22, logo, Ui.VStack(7, title, subtitle));
        stack.HorizontalAlignment = HorizontalAlignment.Center;
        stack.VerticalAlignment = VerticalAlignment.Center;
        Children.Add(stack);
    }
}
