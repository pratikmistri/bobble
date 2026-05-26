using System.Globalization;
using System.IO;
using System.Windows.Data;
using System.Windows.Media.Imaging;

namespace BobbleWin.Views;

public sealed class ChatHeadAvatarConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        var imageName = value as string;
        if (string.IsNullOrWhiteSpace(imageName))
        {
            imageName = "Bobble1";
        }

        var baseDir = AppContext.BaseDirectory;
        var path = Path.Combine(baseDir, "Assets", "HeadAvatars", imageName + ".png");
        if (!File.Exists(path))
        {
            path = Path.Combine(baseDir, "Assets", "HeadAvatars", "Bobble1.png");
        }

        var bmp = new BitmapImage();
        bmp.BeginInit();
        bmp.CacheOption = BitmapCacheOption.OnLoad;
        bmp.UriSource = new Uri(path, UriKind.Absolute);
        bmp.EndInit();
        bmp.Freeze();
        return bmp;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return null!;
    }
}
