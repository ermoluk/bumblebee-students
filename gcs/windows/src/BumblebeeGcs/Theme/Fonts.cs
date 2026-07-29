using Microsoft.UI.Text;
using Microsoft.UI.Xaml.Media;
using Windows.UI.Text;

namespace BumblebeeGcs.Theme;

/// <summary>Спецификация шрифта — порт таблицы `Theme` (typography) из Models.swift, размеры 1:1.</summary>
public readonly record struct FontSpec(double Size, FontWeight Weight, bool Mono = false)
{
    public FontFamily Family => Mono ? Fonts.MonoFamily : Fonts.UiFamily;
}

public static class Fonts
{
    // SF Pro → Segoe UI Variable, SF Mono → Cascadia Mono.
    public static readonly FontFamily UiFamily = new("Segoe UI Variable Text,Segoe UI");
    public static readonly FontFamily MonoFamily = new("Cascadia Mono,Consolas");

    static FontWeight W(ushort w) => new(w);

    public static readonly FontSpec Title      = new(15, W(600));
    public static readonly FontSpec Label      = new(11, W(500));
    public static readonly FontSpec SectionLbl = new(10, W(600));
    public static readonly FontSpec Value      = new(13, W(400), Mono: true);
    public static readonly FontSpec ValueBig   = new(22, W(600), Mono: true);
    public static readonly FontSpec Mono       = new(13, W(400), Mono: true);
    public static readonly FontSpec MonoSmall  = new(10, W(400), Mono: true);
    public static readonly FontSpec Brand      = new(14, W(700));
    public static readonly FontSpec LogoTitle  = new(24, W(700));
    public static readonly FontSpec Body       = new(13, W(400));
    public static readonly FontSpec BodyStrong = new(13, W(600));
    public static readonly FontSpec BodyMed    = new(12, W(500));
    public static readonly FontSpec Button     = new(13, W(600));
    public static readonly FontSpec ButtonSm   = new(12, W(500));
    public static readonly FontSpec Chip       = new(11, W(500));
    public static readonly FontSpec StatValue  = new(17, W(600), Mono: true);
    public static readonly FontSpec HostMono   = new(12, W(600), Mono: true);
    public static readonly FontSpec LogMono    = new(10, W(400), Mono: true);
    public static readonly FontSpec Badge      = new(10, W(700), Mono: true);
    public static readonly FontSpec Micro      = new(8, W(400), Mono: true);
}
