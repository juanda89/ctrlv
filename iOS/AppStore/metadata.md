# App Store listing — Control-V for iOS (paste-ready)

Everything App Store Connect asks for at submission, in the order it asks.
Keep this file in sync with the app; App Review reads the notes literally.

## App Information

- Name: `Control-V`
- Subtitle (30 chars max): `Translate text in any app`
- Bundle ID: `info.controlv.ios`
- SKU: `controlv-ios`
- Primary language: English (U.S.)
- Category: Productivity. Secondary: Utilities.
- Content rights: does not contain third-party content.
- Age rating: 4+ (no objectionable content; answer "No" to every question).

## Version 1.0

**Promotional text (170 chars max)**

> Select text anywhere on your iPhone, translate it, and put the result back in place. One subscription covers your Mac too.

**Description**

> Control-V turns any text on your iPhone into natural, native-sounding writing in the language you choose, without leaving the app you are in.
>
> Three ways to translate:
> • Share sheet: select text in any app, tap Share, choose Control-V, and copy or replace the result.
> • Keyboard: switch to the Control-V keyboard, tap "Translate & Replace", and the text in the field is rewritten in place.
> • System Translate (iOS 18.4 and later): set Control-V as your default translation app and use the Translate menu on selected text; tap Replace to swap it directly.
>
> Choose the target language and tone once per profile: keep the original voice, go formal, casual, or concise, or write your own style instruction. The result reads like a native speaker wrote it, not like a word-for-word translation.
>
> Private by design. Only the text you choose to translate is sent to our servers, over an encrypted connection, and it is never stored or logged there. The keyboard sends nothing until you tap the button.
>
> Control-V Pro is a monthly subscription with a 14-day free trial. One subscription covers your iPhone and the Control-V Mac app: sign in with the same email on both.
>
> Privacy policy: https://control-v.info/privacy
> Terms of use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

**Keywords (100 chars max, comma-separated, no spaces after commas)**

`translate,translator,translation,keyboard,rewrite,grammar,spanish,english,language,writing`

**Support URL**: `https://control-v.info`
**Marketing URL**: `https://control-v.info`
**Privacy Policy URL**: `https://control-v.info/privacy`
**Copyright**: `© 2026 Viko Holdings LLC`

**What's New (1.0)**

> First release.

## Screenshots

Required sizes: 6.9" (iPhone 17 Pro Max: 1320 × 2868) and 6.5" (iPhone 11 Pro Max /
XS Max: 1242 × 2688). `iOS/AppStore/screenshots/` holds the 6.9" set captured from the
simulator; App Store Connect scales 6.9" down for the 6.5" slot if you upload only one set.
Suggested order: translate tab with a result, tone picker, keyboard "Translate & Replace",
system Translate sheet with Replace, account/subscription.

## App Privacy (nutrition label)

Answer "Yes, we collect data from this app", then:

| Data type | Collected | Linked to user | Used for tracking | Purpose |
|---|---|---|---|---|
| User Content → Other User Content (text the user chooses to translate) | Yes | Yes | No | App Functionality |
| Identifiers → User ID (install ID, hashed server-side) | Yes | Yes | No | App Functionality |
| Contact Info → Email Address (only when the user signs in) | Yes | Yes | No | App Functionality |

Everything else: not collected. No third-party SDKs collect data on iOS (TelemetryDeck is
macOS-only). Translation history stays on the device; it is not "collected".

## In-App Purchase

- Type: Auto-Renewable Subscription
- Reference name: `Control-V Pro Monthly`
- Product ID: `info.controlv.pro.monthly` (must match `StoreKitSubscriptionManager.productID`)
- Subscription group: `Control-V Pro`
- Duration: 1 month. Price: USD 4.99 (tier equivalent elsewhere).
- Introductory offer: Free trial, 14 days, new subscribers.
- Localization (English): display name `Control-V Pro`, description `Unlimited translations on iPhone and Mac.`
- Review screenshot for the IAP: the paywall screen.

## App Store Server Notifications

- Production URL: `https://hdfhonbgkkiffhkwoivd.functions.supabase.co/appstore-webhook`
- Sandbox URL: same.
- Version: 2.

## App Review Information

- Sign-in required: Yes. Provide a sandbox tester email + password (create under
  Users and Access → Sandbox → Testers) and note that the app itself uses a 6-digit
  email code: the reviewer can use any email they control, or leave the app in trial mode
  (14 days, no sign-in needed) to test translation.
- Contact: your name, phone, and `info@control-v.info`.

**Notes (paste verbatim)**

> Control-V translates text the user explicitly selects. It works in trial mode without an account, so no sign-in is needed to test translation.
>
> KEYBOARD (Guideline 4.4.1): the Control-V keyboard requests Full Access solely to send text the user explicitly chooses to translate (by tapping "Translate & Replace") to our translation API. The keyboard never logs keystrokes, transmits nothing until the user taps the button, and our server does not store the text (only character counts for rate limiting). Data collected by the keyboard is used exclusively to provide the translation feature.
> To test: Settings → General → Keyboard → Keyboards → Add New Keyboard → Control-V → enable Allow Full Access. Open Notes, type a sentence, long-press the globe key, select Control-V, tap "Translate & Replace".
>
> SHARE EXTENSION: select text in Notes or Safari → Share → Control-V → the translation appears with Copy / Replace.
>
> DEFAULT TRANSLATION APP (iOS 18.4+): Settings → Apps → Default Apps → Translation → Control-V. Then select text anywhere → Translate → Replace.
>
> SUBSCRIPTION: Control-V Pro, USD 4.99/month with a 14-day free trial, purchasable from the paywall in the Account tab. A sandbox tester account is provided above. The same subscription also unlocks our Mac app (sign in with the same email).

## Terms of use

Auto-renewable subscriptions require a Terms of Use link (Guideline 3.1.2). Until
control-v.info has its own terms page, the description links Apple's standard EULA; also
paste that URL in App Store Connect → App Information → License Agreement (leave "Apple
standard" selected).

## Export compliance

`ITSAppUsesNonExemptEncryption` is `false` in every Info.plist: the app only uses HTTPS.
App Store Connect will not ask on each build.

## Release

- Version release: **manually release this version** (so the server-side sandbox switch can be
  flipped first: set the Supabase secret `APPSTORE_ALLOW_SANDBOX` to anything but `true` and
  redeploy `validate-appstore-receipt`, then press Release).
- Phased release: off for 1.0.
