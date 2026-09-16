import ExtensionKit
import SwiftUI
import TranslationUIProvider

/// Default-translation-app extension (iOS 18.4+). Once the user picks
/// Control-V in Settings → Apps → Default Apps → Translation, the system
/// "Translate" item in the text-selection menu of any app opens this sheet
/// with the selected text, and `finish(translation:)` replaces the selection
/// in place when the host app allows it.
@main
final class ControlVTranslationExtension: TranslationUIProviderExtension {
    required init() {}

    var body: some TranslationUIProviderExtensionScene {
        TranslationUIProviderSelectedTextScene { context in
            TranslationProviderView(context: context)
        }
    }
}
