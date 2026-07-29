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

using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace BumblebeeGcs.Controls;

/// <summary>
/// Аналог LazyVGrid(.adaptive(minimum:)): столько равных колонок, сколько
/// влезает при минимальной ширине элемента; высота строки — по максимуму.
/// </summary>
public sealed class AdaptiveGridPanel : Panel
{
    public double MinItemWidth { get; set; } = 190;
    public double Spacing { get; set; } = 12;

    protected override Windows.Foundation.Size MeasureOverride(Windows.Foundation.Size availableSize)
    {
        var w = double.IsInfinity(availableSize.Width) ? 1200 : availableSize.Width;
        var (cols, itemW) = Layout(w);
        double y = 0, rowH = 0;
        var i = 0;
        foreach (var child in Children)
        {
            child.Measure(new Windows.Foundation.Size(itemW, double.PositiveInfinity));
            rowH = Math.Max(rowH, child.DesiredSize.Height);
            if (++i % cols == 0)
            {
                y += rowH + Spacing;
                rowH = 0;
            }
        }
        if (i % cols != 0) y += rowH + Spacing;
        return new Windows.Foundation.Size(w, Math.Max(0, y - Spacing));
    }

    protected override Windows.Foundation.Size ArrangeOverride(Windows.Foundation.Size finalSize)
    {
        var (cols, itemW) = Layout(finalSize.Width);
        double y = 0, rowH = 0;
        var i = 0;
        foreach (var child in Children)
        {
            var col = i % cols;
            child.Arrange(new Windows.Foundation.Rect(col * (itemW + Spacing), y, itemW, child.DesiredSize.Height));
            rowH = Math.Max(rowH, child.DesiredSize.Height);
            if (++i % cols == 0)
            {
                y += rowH + Spacing;
                rowH = 0;
            }
        }
        return finalSize;
    }

    private (int Cols, double ItemW) Layout(double width)
    {
        var cols = Math.Max(1, (int)((width + Spacing) / (MinItemWidth + Spacing)));
        cols = Math.Min(cols, Math.Max(1, Children.Count));
        var itemW = (width - Spacing * (cols - 1)) / cols;
        return (cols, Math.Max(1, itemW));
    }
}
