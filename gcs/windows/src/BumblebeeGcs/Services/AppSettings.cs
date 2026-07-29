using System.Text.Json;
using BumblebeeGcs.Models;

namespace BumblebeeGcs.Services;

/// <summary>Персистентные настройки (замена UserDefaults): lastHost и «флот» знакомых дронов.</summary>
public sealed class AppSettings
{
    public string? LastHost { get; set; }
    public List<KnownDrone> KnownDrones { get; set; } = new();

    private static string Dir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "BumblebeeGCS");
    private static string FilePath => Path.Combine(Dir, "settings.json");

    private static readonly JsonSerializerOptions JsonOpts = new() { WriteIndented = true };

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath)) ?? new AppSettings();
        }
        catch { }
        return new AppSettings();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Dir);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, JsonOpts));
        }
        catch { }
    }
}
