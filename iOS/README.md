# Control-V iOS

Status: **source files written, Xcode project setup pending (manual)**.

The macOS app is built with Swift Package Manager directly. iOS apps with App Store submission require an actual Xcode project (`.xcodeproj`), so this directory contains the iOS source files, ready to be picked up by an Xcode project the user creates once.

## What's already built

```
iOS/
├── Sources/ControlViOS/          ← Main iOS app source files
│   ├── App/
│   │   └── ControlViOSApp.swift          (@main, AppCoordinator)
│   ├── Views/
│   │   ├── RootTabView.swift             (TabView with Translate / History / Account)
│   │   ├── PaywallView.swift             (full-screen paywall, StoreKit 2 native trial UX)
│   │   ├── TranslateTabView.swift        (paste / language picker / translate / copy)
│   │   ├── HistoryTabView.swift          (last 50 translations, swipe to copy)
│   │   ├── AccountTabView.swift          (subscription status + signin link)
│   │   └── SignInScreen.swift            (email + magic code, optional)
│   ├── Services/
│   │   ├── iOSTranslationManager.swift   (wraps backend translate call)
│   │   ├── iOSSettingsStore.swift        (App Group UserDefaults for language/tone)
│   │   └── HistoryStore.swift            (App Group history list)
│   └── Subscription/
│       └── StoreKitSubscriptionManager.swift  (StoreKit 2 with trial intro offer)
├── ShareExtension/
│   └── ShareViewController.swift          (Share Extension entry point + result UI)
└── KeyboardExtension/
    ├── KeyboardViewController.swift       (UIInputViewController — reads selection via
    │                                       textDocumentProxy, replaces in-place)
    └── KeyboardPanelView.swift            (SwiftUI panel: Translate & Replace button)
TranslationExtension/                      (iOS 18.4+ default translation app: the system
    ├── TranslationProviderExtension.swift  Translate menu item opens this sheet; Replace
    └── TranslationProviderView.swift       swaps the selection in place)
Shared/ExtensionBridge.swift               (App Group settings/session/history for all extensions)
```

### Three ways to translate from any app

1. **System Translate menu (iOS 18.4+, the primary path).** `TranslationExtension/`
   is a `TranslationUIProvider` extension (ExtensionKit point
   `com.apple.public.translation-ui-provider`). Once the user picks Control-V in
   Settings → Apps → Default Apps → Translation, the **Translate** item in the
   text-selection menu of any app opens our sheet with the selected text;
   `context.finish(translation:)` replaces the selection in place when the host
   allows it (`allowsReplacement`), otherwise the sheet offers Copy. Requires the
   `com.apple.developer.translation-app` entitlement on the app (self-service
   "Translation" capability, no Apple approval form) and the
   `com.apple.developer.translation-ui-provider.network-access` Info.plist key.
   This is how DeepL, Google Translate, Microsoft Translator and Mate integrate.
2. **Custom keyboard (any iOS).** Also translates what the user just typed with
   nothing selected. Reads `textDocumentProxy.selectedText`, falling back to
   `documentContextBeforeInput`; requires "Allow Full Access".
3. **Share extension.** Select → Share → Control-V → Copy.

`Shared/ExtensionBridge.swift` gives all three the App Group settings, install
ID, session token and history.

All source consumes `ControlVCore` (the Swift Package library at `../Sources/ControlVCore`) for license, auth, providers, models, prompts.

---

## Xcode project (generated, not hand-made)

The project is generated from `iOS/project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). Do not edit `ControlV.xcodeproj` by hand; it is gitignored and
regenerated on demand:

```bash
cd iOS && xcodegen generate
open ControlV.xcodeproj
```

Targets: **Control-V** (app, `info.controlv.ios`), **Control-V Share** (`info.controlv.ios.share`),
**Control-V Keyboard** (`info.controlv.ios.keyboard`). All three share the App Group
`group.info.controlv.shared`, depend on the local `ControlVCore` package, and ship their
own `PrivacyInfo.xcprivacy` (from `iOS/Resources/<target>/`). Info.plist keys (backend URLs,
extension points, `RequestsOpenAccess` for the keyboard) come from `project.yml`.

Simulator build from the command line (no signing):

```bash
cd iOS && xcodebuild -project ControlV.xcodeproj -scheme Control-V -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Before building for a device or archiving, set `DEVELOPMENT_TEAM` in `project.yml`
(Viko Holdings LLC team ID) and regenerate.

**Keyboard test in the simulator:** run the app once → Settings → General → Keyboard →
Keyboards → Add New Keyboard → Control-V Keyboard → enable **Allow Full Access** → in Notes,
long-press the globe key → Control-V → **Translate & Replace**.

### 8. App Store Connect setup

```
1. Create app record:
   - Name: Control-V
   - Bundle ID: info.controlv.ios
   - Primary language: English (or Spanish — your call)

2. Create In-App Purchase (Subscription):
   - Reference name: Control-V Pro
   - Product ID: info.controlv.pro.monthly        ← MUST match StoreKitSubscriptionManager.productID
   - Subscription Group: Control-V Pro
   - Price: $4.99 / month (same as the Mac price for new users)
   - Add Introductory Offer:
     - Type: Free Trial
     - Duration: 14 days
     - Eligibility: New subscribers
   - Localizations: at minimum English

3. Configure App Store Server Notifications V2:
   - URL: https://hdfhonbgkkiffhkwoivd.functions.supabase.co/appstore-webhook
   - Version: V2
   (Edge Function `appstore-webhook` is built; set this URL once the app record exists.)

4. Generate App Store Server API key for receipt validation:
   - Users → Keys → In-App Purchase → +
   - Save the .p8 file securely
```

### 8b. Privacy manifests (required — upload is flagged without them)

All three targets use UserDefaults (a "required reason API"), so each needs a
`PrivacyInfo.xcprivacy` in its bundle or App Store Connect rejects the upload
with ITMS-91053. Pre-written manifests live in `iOS/PrivacyManifests/`:

- `App-PrivacyInfo.xcprivacy` → drag into the **Control-V** (main app) target,
  rename to `PrivacyInfo.xcprivacy` when adding
- `Extension-PrivacyInfo.xcprivacy` → drag one copy into **Control-V Share**
  and one into **Control-V Keyboard**, renamed to `PrivacyInfo.xcprivacy`

In the add dialog: "Copy items if needed" CHECKED (each target needs its own
copy in its bundle), target membership = the respective target only.

### 8c. App Review preparation (do this before submitting)

**Privacy compliance (Guidelines 5.1.1, 5.1.2):**
1. Privacy policy is live at https://control-v.info/privacy (docs/privacy.html) —
   enter this URL in App Store Connect → App Privacy → Privacy Policy URL
2. Complete the App Privacy "nutrition label": declare **User Content**
   (translation text) and **Identifiers** (install ID) + **Email** (if signed in)
   as collected, linked to user, NOT used for tracking
3. The app already links the policy from AccountTabView and PaywallView

**Full Access justification (Guideline 4.4.1) — put this in Review Notes:**

> The Control-V keyboard requests Full Access solely to send text the user
> explicitly chooses to translate (by tapping "Translate & Replace") to our
> translation API. The keyboard never logs keystrokes, transmits nothing
> until the user taps the button, and our server does not store the text
> (only character counts for rate limiting). Data collected by the keyboard
> is used exclusively to provide the translation feature.
>
> To test: Settings → General → Keyboard → Keyboards → Add New Keyboard →
> Control-V → enable Allow Full Access. Then open Notes, type a sentence,
> long-press the globe key, select Control-V, tap "Translate & Replace".

**⚠️ Known 4.4.1 risk — decide before submission:**
Guideline 4.4.1 says keyboards must "remain functional with no network
access". Our keyboard's only feature is translation, which inherently needs
network. Two options:
- **Option A (ship as-is):** many single-purpose utility keyboards pass review
  with a clear Review Notes explanation; rejection risk exists but is appealable
- **Option B (safest):** add a minimal typing layout (QWERTY row) so the
  keyboard "functions" offline — significant extra work, defer unless rejected

Recommendation: try Option A first. If rejected under 4.4.1, build Option B.

### 9. Test in StoreKit sandbox

- Run the app on a real device (or Mac Catalyst) signed in with a Sandbox tester account (App Store Connect → Users and Access → Sandbox Testers).
- The Paywall should show "Start 14-day free trial".
- Tap → Face ID prompt → success → app shows main UI.
- Cancel from Settings → Subscriptions → cancel → app reflects change (within minutes).

---

## Backend (done)

- `validate-appstore-receipt` — the app POSTs the **signed** StoreKit 2 transaction (JWS);
  the server verifies Apple's certificate chain against the pinned Apple Root CA - G3 using
  Apple's official `app-store-server-library`, then upserts `account_subscriptions`
  (provider `appstore`, keyed by `appstore_original_transaction_id`).
- `appstore-webhook` — App Store Server Notifications V2: renewals, billing retry/grace,
  expiry, refunds/revocations update the same row. Idempotent per `notificationUUID`.
- Migration `20260915140000_appstore_subscriptions.sql`.
- Secrets to set: `APPSTORE_BUNDLE_ID` (default `info.controlv.ios`) and
  `APPSTORE_APP_APPLE_ID` (numeric, from App Store Connect; required for production
  verification). Deploy both functions with `--no-verify-jwt`.

## What's NOT done yet

- App Store Connect setup (section 8) and the team ID in `project.yml`.
- Sandbox purchase test on a device, TestFlight, App Store submission.
- Default-translation flow verified on a device (Settings → Apps → Default Apps →
  Translation → Control-V, then select text → Translate → Replace). The simulator
  can't be driven from the command line, so only the sheet's rendering is covered
  by the snapshot test.

---

## Day-to-day after setup

1. Edit any file in `iOS/Sources/` or `iOS/ShareExtension/` from the editor of your choice.
2. Run/build in Xcode.
3. Commit to git as usual; the Xcode project picks up file additions/removals automatically (since we're using "Create groups").

When ControlVCore evolves (we add new public APIs, fix bugs, etc.), the iOS target picks it up automatically because it's a local SPM dependency.

## UI debug flags & screenshots

The app reads NSUserDefaults launch arguments (see `Sources/ControlViOS/App/DebugLaunch.swift`), so every screen can be opened headlessly on the simulator:

```bash
xcrun simctl launch booted info.controlv.ios -ui.tab account -ui.licenseState expired
```

| Flag | Values | Effect |
| --- | --- | --- |
| `-ui.tab` | `translate` `history` `account` | Initial tab |
| `-ui.licenseState` | `trial` `active` `expired` | Sticky license override (validation paths keep it) |
| `-ui.showPaywall 1` | | Opens the paywall (dismissable if the license allows it) |
| `-ui.showSignIn 1` / `-ui.showSetup 1` / `-ui.showFeedback 1` | | Opens that sheet |
| `-ui.sourceText "…"` + `-ui.autoTranslate 1` | | Prefills the editor and translates on launch (real backend) |
| `-ui.seedHistory 1` | | Adds three sample history entries |

Then `xcrun simctl io booted screenshot out.png`. Note: when launched this way the StoreKit configuration is not attached, so the paywall shows its "Pricing isn't available" state; run from Xcode (scheme has `Configuration.storekit`) to see the real price and trial.

The keyboard panel and the share sheet can't be driven from the command line, so a hosted test renders every state to PNG:

```bash
TEST_RUNNER_SNAPSHOT_DIR=/tmp/ctrlv-shots xcodebuild test -project ControlV.xcodeproj -scheme Control-V \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:'Control-V Snapshots'
```

Design tokens and shared components live in `Sources/ControlViOS/Design/` and are compiled into the app **and** both extensions (see `project.yml`).
