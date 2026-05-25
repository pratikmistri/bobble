using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows;

namespace BobbleWin.Utilities;

public abstract class ObservableObject : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    protected bool SetProperty<T>(ref T storage, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(storage, value))
        {
            return false;
        }

        storage = value;
        RaiseOnDispatcher(propertyName);
        return true;
    }

    protected void RaisePropertyChanged([CallerMemberName] string? propertyName = null)
    {
        RaiseOnDispatcher(propertyName);
    }

    private void RaiseOnDispatcher(string? propertyName)
    {
        var handler = PropertyChanged;
        if (handler is null) return;

        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher is null || dispatcher.CheckAccess())
        {
            handler(this, new PropertyChangedEventArgs(propertyName));
        }
        else
        {
            dispatcher.BeginInvoke(new Action(() => handler(this, new PropertyChangedEventArgs(propertyName))));
        }
    }
}
