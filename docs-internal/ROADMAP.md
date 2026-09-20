# Control-V Roadmap

A living list of features, prioritized by impact × effort. Items are notes for product discovery, not commitments.

---

## P0 — Polish v2.x

Things that should land soon to round off the Stripe migration.

- **Apple / Google sign-in** — current email + magic code is fine, but social sign-in cuts 30s of friction. Supabase Auth supports both natively. macOS uses `ASWebAuthenticationSession`.
- **Customer email verification before Stripe** — today we trust whatever they typed. Adding a verified email step before paid checkout reduces accidental "wrong email" support tickets.
- **Forgot which email I used** — common case once a user has a few sessions on different machines. Solution: a "find my account" flow that sends a code to any verified email.
- **Live mode cutover playbook** — checklist for switching Stripe + Resend keys from test to live, with revert plan.

---

## P1 — Naturalness modes (the "human voice" features)

These are the styling toggles you mentioned. They move translations from "correct" to "convincing".

### Tone presets — extension of existing

Today we have Original / Formal / Casual / Concise / Custom. Add:

- **Quick / Texting** — abbreviates, drops articles, lowercases. "tomorrow at 5" → "tmrw at 5". Optimized for messaging apps.
- **Native typist** — keeps natural typos and minor punctuation slips. Doesn't autocorrect "their" vs "they're". Example: "i think were good" stays "creo que estamos bien" (not "Creo que estamos bien").
- **No caps, no periods** — applies to the *output* a stylistic flatten: lowercase everywhere, drops sentence-ending periods (keeps commas / question marks). Distinct mood — works great for Slack, X.
- **Voice-note style** — runs sentences together with commas. Mimics how people actually speak.

### Per-app tone

Auto-switch tone based on the foreground app at translation time:
- WhatsApp / Messages → "Texting"
- Slack → "Casual"
- Mail / Word → "Formal"
- Notes / Obsidian → "Original"

Implementation note: macOS Accessibility already exposes the focused app bundle ID. Cheap to add.

### Emoji density slider

Three levels: none, occasional, generous. The LLM is good at this with a temperature hint. Works well combined with Casual tone for chat use cases.

### "Write like me" learning mode

Optional: opt-in feature where the user pastes 5–10 of their own messages, and we cache an embedding profile. Future translations bias to that style. This is the most differentiated thing on the list — most translation tools don't do voice matching.

---

## P1 — iOS app

Major surface to ship next. Big share of the productivity translation market is on phone (replying to chats, reading articles).

### Distribution
- **App Store** — required for iOS. Same Apple Developer team ID, but separate app record.
- **Subscription** — App Store IAP is the path of least resistance. Stripe is not allowed for digital goods on iOS. So: dual billing system (Stripe on Mac, IAP on iOS), unified by account email at the backend.

### Architecture choices
- **Share extension** — primary entry point. User selects text in any iOS app, taps Share → Control-V → translation appears in a sheet, copies to clipboard.
- **Keyboard extension (later)** — a custom keyboard that translates as you type, showing the result inline. More complex (sandboxed, no network without "Allow Full Access"), but unlocks the in-place workflow that Mac users love.
- **iOS Action extension** for Safari — read foreign-language webpages.

### Reuse from macOS
- `SubscriptionStatus` model — same shape works
- `MagicCodeAuthClient` — pure HTTP, ports directly
- `AccountStore` — replace AES file storage with iOS Keychain
- `LicenseService` state machine — same enum, different UI
- Backend Edge Functions — zero changes

### iOS-only pieces
- StoreKit 2 subscription manager (replaces Stripe checkout on iOS)
- Backend webhook for App Store Server Notifications V2 (similar pattern to Stripe webhook)
- Reuse `account_subscriptions` table with provider="appstore"

### Effort estimate
About 2/3 of the Mac app's complexity. Sharing, keyboard, and StoreKit are the new parts; the rest is already built or trivially portable.

---

## P2 — Power features

Not urgent but high-leverage if user retention goals call for them.

- **History panel** — last N translations, searchable. Lots of users translate the same phrases repeatedly.
- **Glossary / phrase memory** — "always translate 'closing the loop' as 'cerrar el ciclo'". Personal terminology lock.
- **Streaming translations** — show output token-by-token as it streams from the model. Looks faster even when total time is similar.
- **Side-by-side compare** — modifier key while triggering shortcut → show original + translation side-by-side instead of replacing.
- **Multi-pass refinement** — translate, then auto-check by asking "is this natural?". Better quality at higher cost.
- **Voice input** — hold-to-speak, dictate in your language, translate to clipboard.

---

## P2 — Distribution / growth

- **Setapp listing** — reaches macOS power users. Setapp pays a per-active-user fee, so ~$1.50–3 per active subscriber. Makes sense once we have organic Stripe MRR baseline.
- **Localized landing pages** — `/es`, `/pt`, `/de`. Translation tool buyers self-select on language; landing in their native tongue converts better.
- **Affiliate program for power users** — 30% revenue share for first 6 months. Stripe Connect makes payouts easy.
- **Onboarding email sequence** — day 1 (welcome), day 3 (tip on shortcuts), day 7 (tone presets), day 13 (last-chance trial reminder). Resend supports this.

---

## P2 — Reliability

- **Per-language fine-tuning** — current single Grok model is okay everywhere but not best-in-class anywhere. A model router that picks Claude/GPT/Gemini based on the language pair could lift quality. Backend already has provider routing scaffolding.
- **Latency P95 monitoring** — TelemetryDeck shows totals. Adding P95 per language pair surfaces regressions.
- **Offline grace tightening** — current 30 days is generous. After 7 days offline maybe show a soft warning in the UI ("Sign in to keep using"). Doesn't block, just nudges.

---

## P3 — Experimental

Speculative, only if a clear opportunity emerges.

- **Browser extension** — Chrome/Safari, translate selected text on web pages. Subscription shared with Mac.
- **Team plans** — shared glossary across an organization. B2B pricing tier ($15/seat/month).
- **API access** — let other apps integrate Control-V translation. Per-token pricing. Probably premature; only if inbound demand surfaces.
- **AI proofreading mode** — paste text, get same-language polish (not translation). Different muscle, similar tech.
- **Mac dictation alternative** — system dictation is bad. Whisper + LLM cleanup is much better. Could expose under same shortcut framework.

---

## Anti-roadmap

Things we deliberately won't do.

- **Web app** — not the workflow. Productivity is per-OS.
- **Free forever tier** — we have a 14-day trial. A free tier just bleeds API costs and doesn't convert.
- **Self-hostable backend** — distracts from product velocity. People who want this aren't our customers.
- **Translation memory cloud sync** — privacy concern. If we ever offer history, it stays local-only by default.
