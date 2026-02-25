# InstantTranslator — macOS Menu Bar Translation Utility

## Product Vision
The fastest, lowest-friction translation tool for macOS. Select text, press a shortcut, text is replaced. Lives exclusively in the menu bar and feels like a native OS extension.

## Tech Stack
- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI
- **Target:** macOS 14.0+ (Sonoma)
- **Build System:** Swift Package Manager (SPM)
- **Architecture:** MVVM + Services layer
- **LLM Provider:** Anthropic Claude API (HTTP, expandable via `TranslationProvider` protocol)
- **Persistence:** UserDefaults (preferences) + encrypted local storage for API key and license state
- **Dependencies:** [soffes/HotKey](https://github.com/soffes/HotKey) for global shortcuts, [Sparkle](https://sparkle-project.org/) for auto-updates

## Project Structure
```
Sources/InstantTranslator/
  App/
    InstantTranslatorApp.swift    # @main, no WindowGroup (menu bar only)
    AppDelegate.swift             # Status item, popover, icon animations
  Views/
    MenuBarView.swift             # Main popover layout (composes sections)
    StatusSection.swift           # Trial/license status + CTAs
    PreferencesSection.swift      # Language + Tone selectors
    BehaviorSection.swift         # Shortcut, auto-paste, provider, API key
    FooterSection.swift           # Version, about, quit
    Components/
      ToneSelector.swift          # Segmented tab-style picker
      LanguageDropdown.swift      # Language picker
      APIKeyField.swift           # Secure field + reveal toggle
  ViewModels/
    TranslatorViewModel.swift     # Core orchestrator (translate flow)
    SettingsViewModel.swift       # Preferences + API key state
  Services/
    TranslationService.swift      # Provider abstraction + TranslationProvider protocol
    ClaudeProvider.swift          # Anthropic API implementation
    AccessibilityService.swift    # AX-based text selection + replacement
    ClipboardService.swift        # Pasteboard save/restore + key simulation
    HotkeyService.swift           # Global shortcut via HotKey package
    LicenseService.swift          # Trial + Lemon Squeezy license key state machine
    LemonLicenseClient.swift      # Lemon Squeezy activate/validate/deactivate API client
    LemonLicenseStore.swift       # Encrypted storage for license key + instance metadata
    UpdateService.swift           # Sparkle updater wiring
    PromptBuilder.swift           # Constructs system prompts with tone/context
  Models/
    Tone.swift                    # Enum: original, formal, casual, concise
    SupportedLanguage.swift       # 12 languages with BCP-47 codes
    AppSettings.swift             # Persisted preferences (Codable)
    TranslationRequest.swift      # Input model
    TranslationResponse.swift     # Output model
    TranslationError.swift        # Typed errors with user-facing messages
    LicenseState.swift            # Enum: checking, trial, active, expired, invalid
    LemonLicenseModels.swift      # DTOs for Lemon validation + local license record
  Utilities/
    EncryptedAPIKeyStore.swift    # Encrypted API key storage without Keychain prompts
    Constants.swift               # App-wide constants
Resources/
  InstantTranslator.entitlements  # Network + Accessibility
Tests/InstantTranslatorTests/
  PromptBuilderTests.swift
  TranslationServiceTests.swift
  LicenseServiceTests.swift
```

## Core User Flow
1. User selects text in ANY app
2. Presses Ctrl+Shift+<letter> (global hotkey, configurable)
3. App captures text via Accessibility API (fallback: Cmd+C simulation)
4. Sends to Claude API with PromptBuilder-constructed system prompt
5. If auto-paste ON: replaces selected text (AX or Cmd+V) + restores clipboard
6. If auto-paste OFF: copies to clipboard + flashes menu bar icon

## Architecture Decisions
- **No overlay/floating panel:** Feedback via menu bar icon (translating → checkmark). Less intrusive, more native.
- **TranslationProvider protocol:** `ClaudeProvider` now, extensible to OpenAI/others later.
- **PromptBuilder as service:** Separates prompt engineering from HTTP layer.
- **Encrypted API key storage:** API key is encrypted locally before persistence.
- **ClipboardService with save/restore:** Preserves user's clipboard during Cmd+V fallback.
- **soffes/HotKey:** Battle-tested package vs raw CGEvent tap. Simpler, more reliable.
- **@Observable (not ObservableObject):** Modern macOS 14+ pattern, less boilerplate.
- **No App Sandbox for dev:** Accessibility API requires it. Distribution via notarization.

## Coding Conventions
- Swift concurrency (async/await, @MainActor) for all async operations.
- `@Observable` macro for ViewModels (macOS 14+).
- Keep views thin — logic in ViewModels or Services.
- Typed errors (`TranslationError`), never force-unwrap in production.
- Functions under 40 lines. Extract when exceeding.
- Test names: `test_methodName_expectedBehavior_whenCondition`.

## Build & Run
```bash
swift build
swift run InstantTranslator
swift test
```

## Commercial Layer
- 14-day trial tracked via install date in UserDefaults
- Lemon Squeezy validates license keys directly from the app
- License activation is per device (instance ID)
- App supports 30-day offline grace after last successful validation
- `LicenseState.canTranslate` gates translation flow
- Sparkle updates are public and available to all users (no subscription gating)
