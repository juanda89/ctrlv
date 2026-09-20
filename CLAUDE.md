# ctrl+v (Control-V) — macOS menu bar translation utility

## Product
Select text anywhere, press a shortcut, the text is replaced by its translation (or, with a custom profile, corrected in the same language). Lives in the menu bar. Hosted service: users never bring API keys. Landing: https://control-v.info.

## Tech stack
- **Client:** Swift 5.9+, SwiftUI, macOS 14+, SPM. MVVM + services. `@Observable` everywhere.
- **Backend:** Supabase Edge Functions (Deno/TypeScript) + Postgres. Project ref `hdfhonbgkkiffhkwoivd` (named "ctrlv-staging" in the dashboard but it IS production).
- **LLM:** OpenRouter with a fallback chain from the `OPENROUTER_MODELS` secret (comma-separated). `OPENROUTER_PROVIDER_SORT=latency` (secret, set 2026-09-19) routes to the fastest upstream provider: measured ~25% lower model latency at identical cost versus default routing; unset it to A/B (`scripts/benchmark-translate-debug.sh` prints provider, cost and phase timings). The client sends the system prompt (built by `PromptBuilder`); the server sanitizes output.
- **Auth + billing:** email magic code (6 digits) → session token (sliding 30-day expiry, renewed on use) → Stripe subscription tied to the account email. Checkout/portal open in the browser.
- **Updates:** Sparkle, appcast published to GitHub Releases by CI. **Signing:** Developer ID + notarization in CI.
- **Deps:** soffes/HotKey (global shortcuts), Sparkle, TelemetryDeck.

## Layout
```
Sources/ControlVCore/            # Platform-agnostic logic (to be ported to C# for Windows)
  Models/      LicenseState, SubscriptionStatus, SupportedLanguage, Tone, TranslationRequest/Response/Error, FeedbackSubmission, ProviderType
  Services/    LicenseService (trial/active/expired, 30-day offline grace), MagicCodeAuthClient, AccountStore (AES-GCM, per-install salt),
               DeviceIdentityStore (installID), CtrlVCloudProvider (translate endpoint), PromptBuilder, ModelRouter (display only),
               TrialTranslationService, FeedbackClient, FeedbackPromptTracker, TranslationService (TranslationProvider protocol)
  Utilities/   Constants (endpoints from Info.plist keys)
Sources/InstantTranslator/       # macOS shell
  App/         AppDelegate (status item, popover, island), NativePopoverHostingController, TranslationIslandOverlayController,
               MenuPreviewWindowController + MenuSnapshotRenderer (headless popover PNGs)
  Models/      AppSettings (profiles array, legacy-compatible Codable), TranslationProfile
  ViewModels/  TranslatorViewModel (capture → translate → paste flow, debug stages), SettingsViewModel (profiles, selection), FeedbackViewModel
  Services/    AccessibilityService (AX read/replace), ClipboardService (Cmd+C/V simulation, clipboard polling), HotkeyService (one HotKey per profile),
               UpdateService (Sparkle), TelemetryService
  Views/       MenuBarView (composes sections; inline swaps for SignIn/Debug/Feedback), StatusSection, ProfileTabsSection, PreferencesSection,
               BehaviorSection, FeedbackSection, FeedbackInviteBanner, FeedbackView, ShortcutSettingsView, SignInView, FooterSection, Components/
supabase/functions/              # translate, request-magic-code, verify-magic-code, subscription-status, create-checkout-session,
                                 # create-portal-session, stripe-webhook, submit-feedback, _shared/ (openrouter, session, email, stripe, http)
supabase/migrations/             # Schema history (apply via Management API or CLI)
docs/                            # Static site on Vercel (index, download, success, cancel, privacy). CSS is precompiled Tailwind.
scripts/                         # build-release.sh, generate-appcast.sh, build-docs-css.sh, benchmark-*.sh
.github/workflows/release.yml    # Tag vX.Y.Z → build, sign, notarize, DMG, GitHub Release, appcast
windows/                         # Windows client (.NET 8). ControlV.Core = C# port of ControlVCore (builds/tests on any OS:
                                 # `dotnet test windows/ControlV.sln`); ControlV.App (WPF) lands in Phase 2. CI: windows-ci.yml
```

## Core flow
1. Global hotkey fires for a profile (up to 3 profiles, each with its own ⌘⇧letter, language and tone; auto-paste is global).
2. Island overlay shows immediately.
3. Capture: AX selected text → if nil/whitespace, whole-field value for editable roles → else simulated Cmd+C and poll the pasteboard `changeCount` up to 600ms, skipping whitespace-only writes (Google Docs is a canvas and copies asynchronously).
4. POST `/translate` with installID (+ sessionToken when signed in). Server timeline (nothing waits on what it does not need): the OpenRouter call starts speculatively while ONE Postgres round trip (`translate_begin` RPC: identity upsert/sync, session + sliding renewal, subscription, usage counts; verdict in `_shared/access.ts`) decides access and aborts it on rejection; the usage insert runs after the response (`EdgeRuntime.waitUntil`); a request that has not settled after ~3 s + 1 ms/char is hedged with a second identical one. `X-Ctrlv-Debug: 1` adds `timings.rpcMs/modelMs`. Also: rate limits, bare-URL/email/no-letters passthrough, model chain, sanitizer (strip `¿¡—–` unless in source, keep ALL CAPS, preserve leading/trailing whitespace and indentation), fidelity guard (`fidelityIssues` in `_shared/openrouter.ts`: the user turn is wrapped in `<<<TEXT … TEXT>>>`; if the output drops lines/anchors it retries once with a strict prompt, and if it still looks like a reply to the text it returns 422 instead of pasting an invented message).
5. Translation always lands in the clipboard; if auto-paste is on and the focus is editable, replace via AX or simulated Cmd+V.

## Hard-won rules (do not regress)
- **Never present `.sheet` inside the popover.** Use the inline-swap pattern (SignInView, DebugSheet, FeedbackView, ShortcutSettingsView with `onFinish`). Sheets caused focus loss and stale-state edits routed to the wrong profile.
- **Every profile edit is routed by profile id**; never by index fallback. Two profiles can't share a shortcut (`setShortcut` is a no-op on collision + inline error).
- **Tests never touch real stores.** `AccountStore(directoryURL:)` and `UserDefaults(suiteName:)` in tests; the old suite deleted the developer's live session on every run.
- **Key material for local encryption must be stable** (per-install salt). Never derive from `ProcessInfo.hostName` (changes with the network).
- **Whitespace-only is "no text"** at every stage (AX selection, clipboard fallback trigger, local guard). The server trims and rejects.
- **Deploy Edge Functions with `--no-verify-jwt`** (they validate the app's own session token). No CI deploys functions; pushing to main changes nothing server-side. Both local Supabase CLIs hang: use `scripts/deploy-function.sh <slug>` and `scripts/apply-migration.sh <file>` (Management API, need `SUPABASE_ACCESS_TOKEN`).
- **Abuse controls live server-side and fail closed** (security review 2026-09-19): magic codes burn after 5 wrong attempts (`consume_magic_code`), per-network caps on issued codes and on new trial identities (`translate_begin`), `warmupOnly` never reaches the model, all POST endpoints require `Content-Type: application/json`, `anon`/`authenticated` have no table grants (RLS is the second barrier), pg_cron purges usage events (7d), magic codes (24h), expired sessions (7d) and webhook payloads (30d). `APPSTORE_ALLOW_SANDBOX=true` is the private-beta switch: set it to anything else before the iOS launch.
- **Validate behavior empirically**: probe the live endpoint (curl), query the DB (Management API), read the app's Debug panel. Prompt instructions are not guarantees; put invariants in the server sanitizer.
- Existing users' settings must survive every migration (`AppSettings` decodes the legacy flat shape and mirrors profile 0 back for downgrades).

## Debug & verification tooling
- ⋯ → Debug in the popover: last stage, timings, license validation, hotkeys.
- Server timings/provider/cost per request: send `X-Ctrlv-Debug: <CTRLV_DEBUG_TOKEN>` (the secret's value is in `~/.config/ctrlv/debug-token` on the dev Mac; `scripts/fidelity-suite.ts` and `scripts/benchmark-translate-debug.sh` read it from there or from the env). The Supabase secrets API only returns digests, so keep that file.
- Headless popover render: `.build/debug/InstantTranslator --render-menu-snapshot out.png --menu-scenario active|trial|expired|twoprofiles --menu-appearance light|dark` (scenarios lowercase). Extra flags via NSUserDefaults args: `-feedback.translationCount 30`, `-debug.showFeedbackOnLaunch 1`.
- The SPM binary has its own UserDefaults domain but shares `~/Library/Application Support/ctrl+v/` (AccountStore) with the installed app.

## Conventions
- Swift concurrency (`async/await`, `@MainActor`) for all async work; `@Observable` for view models.
- Views thin; logic in view models/services. Typed errors; no force-unwraps in production. Functions under ~40 lines.
- Test names: `test_methodName_expectedBehavior_whenCondition`. Run `swift test` before every release.
- Release: bump `CFBundleShortVersionString` + `CFBundleVersion` in `Resources/Info.plist`, commit, `git tag vX.Y.Z`, push tag → CI publishes. Server-only changes need no app release.
- Docs pages: if Tailwind classes change, run `bash scripts/build-docs-css.sh`.

## Commercial layer
- 14-day trial per installID (server-side `translation_identities`), 50 translations/day, 3000 chars.
- Paid: rate limits per account (burst/daily) from Edge Function secrets. One subscription covers all the user's devices.
- Sessions renew on use; the client keeps a 30-day offline grace after the last successful validation.
- Feedback: in-app ratings/comments → `app_feedback` table + email to `info@control-v.info` (Resend).

## Roadmap pointer
Windows client planned (.NET 8 + WPF, Velopack, Azure Trusted Signing) reusing the backend as-is; ControlVCore is the port scope.
