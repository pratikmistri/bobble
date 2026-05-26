using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media.Animation;
using BobbleWin.Models;

namespace BobbleWin.Views;

/// <summary>
/// Attached properties that drive the working / completion chat-head storyboards explicitly.
/// We can't rely on <c>DataTrigger.EnterActions</c>/<c>ExitActions</c> because each streaming
/// chunk replaces <c>Sessions[i]</c> wholesale, which swaps the item container's DataContext.
/// On DataContext swap WPF re-evaluates triggers against the new value but does NOT fire
/// <c>ExitActions</c> for the previous value — so a Forever working storyboard started under the
/// old context kept running even after <c>State.Kind</c> transitioned back to <c>Idle</c>.
///
/// This attached property is re-applied on every DataContext swap (because it's bound), so we
/// can deterministically Begin/Stop the storyboards in the property-changed callback.
/// </summary>
public static class BobbleAnimations
{
    public static readonly DependencyProperty IsWorkingProperty = DependencyProperty.RegisterAttached(
        "IsWorking", typeof(bool), typeof(BobbleAnimations),
        new PropertyMetadata(false, OnIsWorkingChanged));

    public static void SetIsWorking(DependencyObject obj, bool value) => obj.SetValue(IsWorkingProperty, value);
    public static bool GetIsWorking(DependencyObject obj) => (bool)obj.GetValue(IsWorkingProperty);

    private static readonly DependencyProperty WorkingStoryboardProperty = DependencyProperty.RegisterAttached(
        "WorkingStoryboard", typeof(Storyboard), typeof(BobbleAnimations),
        new PropertyMetadata(null));

    private static void OnIsWorkingChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not FrameworkElement target)
        {
            return;
        }

        var nowWorking = (bool)e.NewValue;
        var wasWorking = (bool)e.OldValue;

        if (nowWorking && !wasWorking)
        {
            StartWorking(target);
        }
        else if (!nowWorking && wasWorking)
        {
            StopWorking(target);
            PlayCompletion(target);
        }
        else if (!nowWorking)
        {
            // Defensive: ensure no stale clock survives (e.g. when this element was recycled
            // by ItemsControl onto a different DataContext that's already Idle).
            StopWorking(target);
        }
    }

    private static void StartWorking(FrameworkElement target)
    {
        if (target.GetValue(WorkingStoryboardProperty) is Storyboard)
        {
            return;
        }

        if (target.TryFindResource("WorkingBobble") is not Storyboard template)
        {
            return;
        }

        var clone = template.Clone();
        clone.Begin(target, HandoffBehavior.SnapshotAndReplace, isControllable: true);
        target.SetValue(WorkingStoryboardProperty, clone);
    }

    private static void StopWorking(FrameworkElement target)
    {
        if (target.GetValue(WorkingStoryboardProperty) is Storyboard active)
        {
            try
            {
                active.Stop(target);
                active.Remove(target);
            }
            catch
            {
                // Storyboard may have already detached when the visual was unloaded.
            }

            target.ClearValue(WorkingStoryboardProperty);
        }
    }

    private static void PlayCompletion(FrameworkElement target)
    {
        if (target.TryFindResource("CompletedJump") is not Storyboard template)
        {
            return;
        }

        var clone = template.Clone();
        clone.Begin(target);
    }
}

/// <summary>
/// Converts <see cref="SessionStateKind"/> to a bool indicating the working state, used to drive
/// <see cref="BobbleAnimations.IsWorkingProperty"/>.
/// </summary>
public sealed class SessionStateKindIsRunningConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return value is SessionStateKind kind && kind == SessionStateKind.Running;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => SessionStateKind.Idle;
}
