using System.Windows.Automation;

namespace ControlV.App.Services;

internal readonly record struct CaptureResult(string? Text, bool IsEditable, bool UsedClipboard, string Stage);

/// Reads the text to translate: UI Automation selection first, whole value of
/// an editable control second, simulated Ctrl+C with clipboard polling last.
/// Whitespace-only counts as nothing at every step.
internal sealed class TextCaptureService
{
    private readonly ClipboardService _clipboard;

    public TextCaptureService(ClipboardService clipboard) => _clipboard = clipboard;

    public async Task<CaptureResult> CaptureAsync()
    {
        var (uiaText, isEditable, uiaStage) = ReadViaAutomation();
        if (!string.IsNullOrWhiteSpace(uiaText)) return new CaptureResult(uiaText, isEditable, false, uiaStage);

        var baseline = _clipboard.SequenceNumber;
        _clipboard.SimulateCopy();
        var text = await _clipboard.WaitForCopiedTextAsync(baseline);
        var stage = $"{uiaStage}; clipboard fallback → {(string.IsNullOrWhiteSpace(text) ? "nothing" : $"{text!.Length} chars")}";
        // When automation said nothing, assume the surface accepts paste (the same
        // Cmd+V-fallback rule that makes Google Docs work on macOS).
        return new CaptureResult(string.IsNullOrWhiteSpace(text) ? null : text, isEditable || uiaText is null, true, stage);
    }

    private static (string? Text, bool IsEditable, string Stage) ReadViaAutomation()
    {
        try
        {
            var element = AutomationElement.FocusedElement;
            if (element is null) return (null, true, "UIA: no focused element");

            var controlType = element.Current.ControlType;
            var isEditable = controlType == ControlType.Edit || controlType == ControlType.Document || controlType == ControlType.ComboBox;

            if (element.TryGetCurrentPattern(TextPattern.Pattern, out var textPatternObj) && textPatternObj is TextPattern textPattern)
            {
                var selection = textPattern.GetSelection();
                var selected = string.Join("", selection.Select(r => r.GetText(-1)));
                if (!string.IsNullOrWhiteSpace(selected)) return (selected, isEditable, "UIA: selection");
            }

            if (isEditable && element.TryGetCurrentPattern(ValuePattern.Pattern, out var valueObj) && valueObj is ValuePattern value)
            {
                var whole = value.Current.Value;
                if (!string.IsNullOrWhiteSpace(whole)) return (whole, true, "UIA: whole field value");
            }

            return (null, isEditable, $"UIA: empty ({controlType.ProgrammaticName})");
        }
        catch (Exception e) when (e is ElementNotAvailableException or InvalidOperationException or System.Runtime.InteropServices.COMException)
        {
            return (null, true, $"UIA: error {e.GetType().Name}");
        }
    }
}
