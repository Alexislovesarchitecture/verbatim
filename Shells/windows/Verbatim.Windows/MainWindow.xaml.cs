using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Verbatim.Windows.Core;
using Windows.System;

namespace Verbatim.Windows;

public sealed partial class MainWindow : Window
{
    private readonly WindowsShellState state = new();
    private WindowsShellSnapshot? snapshot;
    private bool isRendering;
    private bool hasInitialized;

    public MainWindow()
    {
        InitializeComponent();
        Activated += MainWindow_Activated;
    }

    private async void MainWindow_Activated(object sender, WindowActivatedEventArgs args)
    {
        if (hasInitialized)
        {
            return;
        }

        hasInitialized = true;
        snapshot = await state.LoadAsync();
        Render();
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        snapshot = await state.ReloadAsync();
        Render();
    }

    private async void ProviderComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (isRendering || ProviderComboBox.SelectedItem is not SelectorOption option)
        {
            return;
        }

        snapshot = await state.SetSelectedProviderAsync(option.Value);
        Render();
    }

    private async void LanguageComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (isRendering || LanguageComboBox.SelectedItem is not SelectorOption option)
        {
            return;
        }

        snapshot = await state.SetLanguageAsync(option.Value);
        Render();
    }

    private async void WhisperModelComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (isRendering || WhisperModelComboBox.SelectedItem is not SelectorOption option)
        {
            return;
        }

        snapshot = await state.SetModelAsync(ProviderIds.Whisper, option.Value);
        Render();
    }

    private async void ParakeetModelComboBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (isRendering || ParakeetModelComboBox.SelectedItem is not SelectorOption option)
        {
            return;
        }

        snapshot = await state.SetModelAsync(ProviderIds.Parakeet, option.Value);
        Render();
    }

    private async void InstallModelButton_Click(object sender, RoutedEventArgs e)
    {
        ModelProgressBar.Visibility = Visibility.Visible;
        ModelProgressBar.IsIndeterminate = true;
        ModelProgressTextBlock.Text = "Starting model install...";
        var progress = new Progress<double?>(value =>
        {
            if (value.HasValue)
            {
                ModelProgressBar.IsIndeterminate = false;
                ModelProgressBar.Value = value.Value;
                ModelProgressTextBlock.Text = $"Download progress: {value.Value:P0}";
            }
            else
            {
                ModelProgressBar.IsIndeterminate = true;
                ModelProgressTextBlock.Text = "Downloading model...";
            }
        });

        snapshot = await state.InstallSelectedModelAsync(progress, CancellationToken.None);
        ModelProgressBar.Visibility = Visibility.Collapsed;
        ModelProgressBar.IsIndeterminate = false;
        Render();
    }

    private async void CopyLatestButton_Click(object sender, RoutedEventArgs e)
    {
        snapshot = await state.CopyLatestTranscriptAsync();
        Render();
    }

    private async void RecordButton_Click(object sender, RoutedEventArgs e)
    {
        snapshot = await state.ToggleRecordingAsync();
        Render();
    }

    private async void OpenPermissionSettingsButton_Click(object sender, RoutedEventArgs e)
    {
        if (snapshot?.Permission.ActionUri is not string actionUri || string.IsNullOrWhiteSpace(actionUri))
        {
            return;
        }

        _ = await Launcher.LaunchUriAsync(new Uri(actionUri));
    }

    private void Render()
    {
        if (snapshot is null)
        {
            return;
        }

        isRendering = true;
        try
        {
            var paths = snapshot.Paths;
            Title = $"Verbatim - {paths.Root}";
            StatusTextBlock.Text = snapshot.StatusMessage ?? "Windows shell ready.";
            ProviderDetailTextBlock.Text = $"Selected provider: {ProviderTitle(snapshot.SelectedProvider)}\nActive on this system: {ProviderTitle(snapshot.EffectiveProvider)}";
            SelectedProviderMessageTextBlock.Text = snapshot.SelectedProvider == snapshot.EffectiveProvider
                ? "The selected provider is active on this system."
                : "The selected provider is stored as preference, but Verbatim will fall back to the active supported provider on this system.";
            PermissionTextBlock.Text = snapshot.Permission.Message;
            PathsTextBlock.Text = $"Settings: {paths.SettingsFile}\nHistory: {paths.HistoryDatabase}\nModels: {paths.Models}\nRuntime: {paths.Runtime}";
            FocusTextBlock.Text = $"{snapshot.FocusContext.AppName}\nWindow: {snapshot.FocusContext.WindowTitle ?? "Unavailable"}\nFocused control: {snapshot.FocusContext.FocusedControlClass ?? "Unavailable"}\n{snapshot.FocusContext.Note ?? string.Empty}";

            ProviderComboBox.ItemsSource = ProviderOptions(snapshot.Providers);
            ProviderComboBox.DisplayMemberPath = nameof(SelectorOption.Label);
            ProviderComboBox.SelectedValuePath = nameof(SelectorOption.Value);
            ProviderComboBox.SelectedValue = snapshot.SelectedProvider;

            LanguageComboBox.ItemsSource = LanguageOptions(snapshot.CurrentLanguageOptions);
            LanguageComboBox.DisplayMemberPath = nameof(SelectorOption.Label);
            LanguageComboBox.SelectedValuePath = nameof(SelectorOption.Value);
            LanguageComboBox.SelectedValue = snapshot.Settings.PreferredLanguages.ForProvider(snapshot.SelectedProvider);

            WhisperModelComboBox.ItemsSource = ModelOptions(snapshot.WhisperModels);
            WhisperModelComboBox.DisplayMemberPath = nameof(SelectorOption.Label);
            WhisperModelComboBox.SelectedValuePath = nameof(SelectorOption.Value);
            WhisperModelComboBox.SelectedValue = snapshot.Settings.SelectedWhisperModelID;

            ParakeetModelComboBox.ItemsSource = ModelOptions(snapshot.ParakeetModels);
            ParakeetModelComboBox.DisplayMemberPath = nameof(SelectorOption.Label);
            ParakeetModelComboBox.SelectedValuePath = nameof(SelectorOption.Value);
            ParakeetModelComboBox.SelectedValue = snapshot.Settings.SelectedParakeetModelID;

            InstallModelButton.IsEnabled = snapshot.SelectedProvider != ProviderIds.AppleSpeech;
            RecordButton.Content = snapshot.IsRecording ? "Stop Recording" : "Start Recording";

            ProviderSummaryListView.ItemsSource = snapshot.Providers.Select(provider =>
                $"{provider.Title}\nSelection: {(provider.IsSelected ? "selected" : "visible")} | Activation: {(provider.IsEffective ? "active" : "fallback/blocked")}\nCapability: {provider.Capability.Kind}\nReadiness: {provider.Readiness.Message}\nRuntime: {provider.Runtime?.State ?? "n/a"}");
            RuntimeListView.ItemsSource = snapshot.RuntimeSnapshots.Select(pair =>
                $"{ProviderTitle(pair.Key)} runtime\nBinary: {pair.Value.BinaryName}\nPresent: {pair.Value.BinaryPresent}\nState: {pair.Value.State}\nEndpoint: {pair.Value.Endpoint ?? "n/a"}\nLast error: {pair.Value.LastError ?? "none"}");
            DiagnosticsListView.ItemsSource = snapshot.Diagnostics.Select(item =>
                $"{ProviderTitle(item.Provider)}\n{item.SummaryLine}{(string.IsNullOrWhiteSpace(item.LastError) ? string.Empty : $"\nLast error: {item.LastError}")}");
            TipsListView.ItemsSource = snapshot.Tips;
            HistoryListView.ItemsSource = snapshot.HistoryItems.Select(item =>
                $"{DateTimeOffset.FromUnixTimeMilliseconds(item.TimestampMs).ToLocalTime():g} [{ProviderTitle(item.Provider)} / {item.Language}]\nOriginal: {item.OriginalText}\nFinal: {item.FinalPastedText}{(string.IsNullOrWhiteSpace(item.Error) ? string.Empty : $"\nError: {item.Error}")}");
            DictionaryListView.ItemsSource = snapshot.DictionaryEntries.Select(item => $"{item.Phrase}\n{item.Hint}");
        }
        finally
        {
            isRendering = false;
        }
    }

    private static List<SelectorOption> ProviderOptions(IEnumerable<ProviderShellSnapshot> providers)
        => providers.Select(provider => new SelectorOption(provider.ProviderId, $"{provider.Title} ({provider.Readiness.Message})")).ToList();

    private static List<SelectorOption> LanguageOptions(IEnumerable<LanguageSelection> languages)
        => languages.Select(language => new SelectorOption(language.Identifier, LanguageTitle(language.Identifier))).ToList();

    private static List<SelectorOption> ModelOptions(IEnumerable<ModelDescriptor> models)
        => models.Select(model => new SelectorOption(model.Id, $"{model.Name} - {model.Detail} ({model.SizeLabel})")).ToList();

    private static string ProviderTitle(string providerId) => providerId switch
    {
        "apple_speech" => "Apple Speech",
        "parakeet" => "Parakeet",
        _ => "Whisper",
    };

    private static string LanguageTitle(string identifier) => identifier switch
    {
        "auto" => "Auto-detect",
        "en" => "English",
        "en-US" => "English (United States)",
        "es" => "Spanish",
        "es-ES" => "Spanish (Spain)",
        "pt" => "Portuguese",
        "pt-BR" => "Portuguese (Brazil)",
        "ru" => "Russian",
        "ru-RU" => "Russian (Russia)",
        _ => identifier,
    };

    private sealed record SelectorOption(string Value, string Label);
}
}
