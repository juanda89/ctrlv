# Control-V iOS

Status: **ready to archive** (team ID, app icon and privacy manifests for all four targets are in `project.yml`; App Store Connect setup pending, see section 8).

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

### The keyboard is a full keyboard

`KeyboardExtension/KeyboardLayoutView.swift` draws a standard QWERTY (letters,
numbers, symbols, shift with caps lock, repeating delete, globe, return) so the
user can leave Control-V enabled as their keyboard. `KeyboardPanelView` is now
just the bar above the keys: Translate, target language, tone, and the
translating/done/error states. The first version replaced the whole keyboard
with a translation panel, which forced a keyboard switch for every translation
and another one to keep typing.

Key widths are floored to a device pixel (`floorToPixel`); ten fractional key
widths rounded up overflow the row and clip the last key.

### Setup status is detected, not asked

Verified end to end on the iOS 26.5 simulator with `Tests/UITests/SetupFlowUITests.swift`
(it drives the real Settings app and the real keyboard switcher):

- **Keyboard added** — read from the enabled-keyboards list iOS keeps in the global
  preferences: `UserDefaults.standard["AppleKeyboards"]` contains
  `info.controlv.ios.keyboard` (that is the exact string Settings writes). No extension
  needs to run for this, and the status flips as soon as the user comes back from Settings.
- **Keyboard ready / no Full Access** — only the keyboard knows, so it reports itself when it
  appears, through two channels: a mark in the App Group (worked without Full Access on the
  simulator, but Apple documents that unprivileged keyboards may be denied the shared
  container) and a Darwin notification (`SetupState.Signal`) that the app turns into its own
  App Group record. The newest report wins.
- **Translate menu (default translation app)** — invisible to the app (`UIApplication.Category`
  only covers the web browser), so the translation extension reports itself the same way the
  first time it runs. The setup sheet has a "Try it here" text field for exactly that: select
  the sample, tap Translate in the edit menu (second page, behind the chevron), and the sheet
  turns green and closes itself. The same field is where the keyboard is opened once.
- There is no "I already did it" button any more: builds 1–4 had one, labelled "It's on", and
  it read as a status, which is how a wrong status got recorded.

### The keyboard is measured against the system one

`KeyboardLayoutView` reproduces the iOS 26 keyboard pixel for pixel on a 402 pt iPhone
(measured from screenshots of the real one in the same simulator): 43 pt keys, 6 pt between
keys, 11 pt between rows, 6.5 pt margins, circular 8 pt corners, no shadow, every key the same
colour (white / `(64,64,65)` in dark mode, glyphs black / white), 22 pt letters (17 pt cap
height), a blank space bar and a return glyph. Rows land at the same y as the system's
(591/645/699/753) and the keyboard top edge too (540), because `KeyboardPanelView.bandHeight`
reserves the 51 pt the system keeps for its predictive bar (35 pt in our view plus the
16 pt lip iOS draws above a third-party keyboard). Two reasons for that band: apps do not
reflow when the user switches keyboards, and the key previews of the top row have room to
rise — an extension's window clips anything outside it, so there is no other way. The band
also hosts the "Translating / Replaced" strip instead of covering the keys.

`KeyView` handles what a `Button` cannot: the character preview on touch down (with the
keyboard click, which needs `ClickingInputView` to opt in), the accent strip after a 420 ms
hold with slide-to-pick (Spanish variants first), and commit on touch up. Modifier keys darken
while pressed; delete repeats after 400 ms. Double space types ". " like the system.

The keys are anchored to the **bottom** of the input view: iOS first lays a keyboard out in a
taller view (442 pt on the simulator) and shrinks it a frame later, and top-aligned keys showed
up mid-screen for that frame — the "keyboard jumps into place" glitch of builds 1–4.

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

`DEVELOPMENT_TEAM` in `project.yml` is the Viko Holdings LLC team (5ZFYF422LX); Xcode's
automatic signing registers the extension bundle IDs and the App Group on first archive.

**Keyboard test in the simulator:** run the app once → Settings → General → Keyboard →
Keyboards → Add New Keyboard → Control-V Keyboard → enable **Allow Full Access** → in Notes,
long-press the globe key → Control-V → **Translate & Replace**.

### 8. App Store Connect setup

**Done on 2026-09-20 (via the browser, Account Holder session):** app record
**Control-V** (Apple ID `6814210564`, SKU `controlv-ios`, bundle `info.controlv.ios`),
subtitle, categories (Productivity / Utilities), content rights, age rating 4+,
App Privacy published (Email Address, Other User Content, User ID — app functionality,
linked, no tracking), privacy policy URL, pricing Free in 175 countries (Mac and
Vision Pro opted out), App Store Server Notifications prod + sandbox → `appstore-webhook`,
subscription group **Control-V Pro** (`22399702`) with **Control-V Pro Monthly**
(`info.controlv.pro.monthly`, Apple ID `6814211123`): 1 month, USD 4.99 base, all
countries, en-US display name/description, introductory offer **free for 2 weeks**
from Sep 20 2026 (no end date). Version 1.0 metadata, keywords, URLs, copyright,
review contact and review notes are filled; release is set to manual. Supabase secret
`APPSTORE_APP_APPLE_ID=6814210564` is set. The four App IDs and the App Group were
registered by Xcode automatic signing (team `5ZFYF422LX`).

### Uploading a build

One command, no Xcode window, no Apple ID prompt:

```
bash scripts/ios-upload.sh --bump
```

It bumps `CURRENT_PROJECT_VERSION` in `project.yml`, regenerates the project, archives,
re-signs and uploads. Processing on App Store Connect takes a few minutes; the internal
TestFlight group "Control-V team" has *access to all builds*, so a processed build reaches
the testers' phones with no further action. Check state without opening the browser:

```
node scripts/asc-api.js GET "/v1/builds?filter[app]=6814210564&limit=3&fields[builds]=version,processingState"
```

**Signing is manual on purpose.** The team's App Store Connect API key (`7325UTJ2UZ`, App
Manager, issuer `425dc43b-2d68-4902-8a14-6935a90efa9a`, private key in
`~/.appstoreconnect/private_keys/`) authenticates fine but Apple refuses *cloud signing*
for it, so `-allowProvisioningUpdates` cannot mint App Store profiles. Instead:

- the Apple Distribution certificate is created through the API and its private key lives
  in a dedicated keychain, `controlv-signing.keychain-db` (password in
  `~/.config/ctrlv/signing-keychain-password`), so no login-keychain prompt can block an
  unattended upload;
- the four `ControlV AppStore <target>` profiles are created through the API and pinned by
  name in `ExportOptions.plist`;
- `bash scripts/ios-signing-setup.sh` reissues the profiles (add `--cert` on a new Mac, or
  when the certificate expires — the current one runs to 2027-09-21).

Signing into Xcode with an Apple Account is no longer needed. It used to be, and it broke:
`xcodebuild` reads accounts from disk, and the GUI's account list was empty on disk
("Failed to find an account with App Store Connect access for team 5ZFYF422LX").

Two things bit on the first uploads and are now fixed in `project.yml`: XcodeGen's
per-target default `TARGETED_DEVICE_FAMILY = "1,2"` overrides the project-level value (now
pinned to `"1"` on every target), and a portrait-only app must set `UIRequiresFullScreen`
or App Store Connect rejects the upload (ITMS-90474).

**Version 1.0 (build 1) submitted for review on 2026-09-20.** Screenshots must be
**6.5"** (1284 x 2778), not 6.9" — generate them with
`sips -z 2778 1284 in.png --out out.png` (see `iOS/AppStore/screenshots/6.5-inch/`).
Leave "Sign-in required" unchecked in App Review Information: the app works in trial
mode with no account, and checking it demands demo credentials.

**Still pending in App Store Connect:** Paid Apps Agreement + banking + tax forms
(Account Holder only — Diego), EU trader status (Business → Compliance, Admin can do
it), the IAP review screenshot (paywall PNG) on the subscription, the 6.9" screenshots
on version 1.0 (`iOS/AppStore/screenshots/`), a sandbox tester (Users and Access →
Sandbox), and the first build (TestFlight). Historical checklist follows.


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

### 8b. Privacy manifests (done)

Every target that touches UserDefaults (a "required reason API") ships a
`PrivacyInfo.xcprivacy` from `iOS/Resources/<target>/`, wired through `project.yml`
(App, Share, Keyboard and Translation). The simulator build's bundles were checked
on 2026-09-20: all four contain the manifest. The app icon lives in
`iOS/Resources/App/Assets.xcassets` (1024×1024, no alpha, flattened from the macOS mark).
Debug launch arguments (`DebugLaunch.swift`) compile to no-ops in Release.

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

- App Store Connect setup (section 8): app record, subscription, server notification URL,
  sandbox tester, and the numeric App Apple ID → `APPSTORE_APP_APPLE_ID` secret.
- Sandbox purchase test on a device, TestFlight, App Store submission.
- Default-translation flow on a real device. Verified by JD in the iOS 26.5
  simulator on 2026-09-16 (Settings → Apps → Default Apps → Translation →
  Control-V, then select text → Translate → Replace); the snapshot test covers
  the sheet's rendering.

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
