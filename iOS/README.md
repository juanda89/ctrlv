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
└── ShareExtension/
    └── ShareViewController.swift          (Share Extension entry point + result UI)
```

All source consumes `ControlVCore` (the Swift Package library at `../Sources/ControlVCore`) for license, auth, providers, models, prompts.

---

## Manual Xcode setup (one-time)

You'll do this once in Xcode. After that, day-to-day iOS work is just editing files we already added and rebuilding.

### 1. Create the Xcode project

```
Open Xcode → File → New → Project
  Choose: iOS → App
  Product name: Control-V
  Bundle identifier: info.controlv.ios       (or whatever you prefer; must match App Store Connect)
  Interface: SwiftUI
  Language: Swift
  Min deployment: iOS 17.0
  Save inside: iOS/  (resulting in iOS/Control-V.xcodeproj)
```

Xcode generates:
- `iOS/Control-V/ContentView.swift` ← delete this
- `iOS/Control-V/Control_VApp.swift` ← delete this

### 2. Add source files to the project

In Xcode's left sidebar, right-click the project → **Add Files to "Control-V"** → select the `iOS/Sources/ControlViOS/` folder. Choose **Create groups** (not folder references).

### 3. Add ControlVCore as a local Swift Package dependency

```
File → Add Package Dependencies
  Click "Add Local..."
  Choose the repository root (the folder containing Package.swift)
  Select the ControlVCore product
  Add to target: Control-V
```

### 4. Configure App Group capability

```
Project settings → Signing & Capabilities → + Capability → App Groups
  Add: group.info.controlv.shared
```

This is what lets the Share Extension share session token + settings + history with the main app.

### 5. Add the Share Extension target

```
File → New → Target → iOS → Share Extension
  Product name: Control-V Share
  Bundle ID: info.controlv.ios.share
  Embed in: Control-V (main app)
```

Xcode generates a `Control-V Share/` directory. Replace its `ShareViewController.swift` with the one in `iOS/ShareExtension/ShareViewController.swift` (or drag the file in).

Add the same App Group capability to the Share Extension target. Add `ControlVCore` as a dependency on the Share Extension target too.

### 6. Configure the Share Extension Info.plist

Edit `Info.plist` of the Share Extension target. Set under `NSExtension`:

```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionAttributes</key>
    <dict>
        <key>NSExtensionActivationRule</key>
        <dict>
            <key>NSExtensionActivationSupportsText</key>
            <true/>
            <key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
            <integer>1</integer>
        </dict>
    </dict>
    <key>NSExtensionMainStoryboard</key>
    <string>MainInterface</string>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.share-services</string>
</dict>
```

Or, since we use a UIViewController directly, replace `NSExtensionMainStoryboard` with `NSExtensionPrincipalClass = ShareViewController` in Info.plist.

### 7. Configure the main app Info.plist

Add to the main app's `Info.plist`:

```xml
<key>CtrlVTranslationAPIURL</key>
<string>https://hdfhonbgkkiffhkwoivd.functions.supabase.co/translate</string>
<key>CtrlVAuthAPIBaseURL</key>
<string>https://hdfhonbgkkiffhkwoivd.functions.supabase.co</string>
<key>NSUserActivityTypes</key>
<array>
    <string>info.controlv.translate</string>
</array>
```

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
   - Price: $8.99 / month
   - Add Introductory Offer:
     - Type: Free Trial
     - Duration: 14 days
     - Eligibility: New subscribers
   - Localizations: at minimum English

3. Configure App Store Server Notifications V2:
   - URL: https://hdfhonbgkkiffhkwoivd.functions.supabase.co/appstore-webhook
   - Version: V2
   (We'll build the appstore-webhook Edge Function in a later phase.)

4. Generate App Store Server API key for receipt validation:
   - Users → Keys → In-App Purchase → +
   - Save the .p8 file securely
```

### 9. Test in StoreKit sandbox

- Run the app on a real device (or Mac Catalyst) signed in with a Sandbox tester account (App Store Connect → Users and Access → Sandbox Testers).
- The Paywall should show "Start 14-day free trial".
- Tap → Face ID prompt → success → app shows main UI.
- Cancel from Settings → Subscriptions → cancel → app reflects change (within minutes).

---

## What's NOT done yet

- iOS-specific backend Edge Functions (Phase 3):
  - `validate-appstore-receipt` — verifies StoreKit transactions server-side
  - `appstore-webhook` — handles Apple Server Notifications V2 (renewals, cancellations)
  - `_shared/appstore.ts` — JWS verification helpers
- Backend migration: `appstore_original_transaction_id` column on `account_subscriptions`
- TestFlight + App Store submission (Phase 5)

The current iOS source compiles **standalone** against ControlVCore. Once the Xcode project is set up, you can build & run the iOS app immediately. Subscriptions will work locally via StoreKit; backend sync happens once Phase 3 lands.

---

## Day-to-day after setup

1. Edit any file in `iOS/Sources/` or `iOS/ShareExtension/` from the editor of your choice.
2. Run/build in Xcode.
3. Commit to git as usual; the Xcode project picks up file additions/removals automatically (since we're using "Create groups").

When ControlVCore evolves (we add new public APIs, fix bugs, etc.), the iOS target picks it up automatically because it's a local SPM dependency.
