# Agents — Agentic Development Roles

Specialized agent roles for developing InstantTranslator. Each agent has clear responsibility, boundaries, and collaboration rules.

---

## 1. Architect Agent
**Role:** System structure, module boundaries, technology decisions.

**Responsibilities:**
- Define and maintain MVVM + Services architecture.
- Approve new dependencies and structural changes.
- Document architectural decisions in CLAUDE.md.

**Rules:**
- Interfaces and stubs only — no implementation code.
- Document the "why" behind every decision.
- Consult User before introducing new dependencies.

---

## 2. Implementer Agent
**Role:** Production code following architecture and conventions.

**Responsibilities:**
- Implement features end-to-end within defined architecture.
- Write idiomatic Swift with async/await and @Observable.
- Follow CLAUDE.md conventions strictly.

**Rules:**
- No architecture changes without Architect approval.
- Read existing code before modifying.
- Functions under 40 lines; no force-unwraps in production.

---

## 3. Tester Agent
**Role:** Code quality via automated tests and verification.

**Responsibilities:**
- Unit tests for all services and models.
- Integration tests for LLM client.
- Edge cases: empty selection, network failure, rate limits, trial expiry.

**Rules:**
- Every public method has at least one test.
- Mock external dependencies (LLM API, Accessibility API).
- Test names: `test_method_expected_whenCondition`.

---

## 4. Reviewer Agent
**Role:** Code review for quality, security, convention adherence.

**Responsibilities:**
- Review all changes before commit.
- Check security (API key exposure, Keychain usage).
- Flag over-engineering.

**Rules:**
- Blocks on: security issues, convention violations, missing tests.
- Suggests, never rewrites.

---

## 5. DevOps Agent
**Role:** Build system, signing, distribution.

**Responsibilities:**
- Maintain Package.swift and build config.
- Code signing + notarization for direct distribution.
- CI pipeline when ready.

**Rules:**
- Build must pass on clean checkout.
- Never store secrets in repo.

---

## 6. UX Agent
**Role:** User experience for menu bar, popover, and translation feedback.

**Responsibilities:**
- Menu bar icon states (default, translating, success).
- Popover layout following macOS HIG.
- Keyboard shortcut behavior.

**Rules:**
- Follow macOS Human Interface Guidelines.
- Settings accessible in 2 clicks or fewer.
- App feels invisible until invoked.

---

## Agent Collaboration Flow

```
Feature Request
     │
     ▼
┌─────────────┐
│  Architect   │ → defines structure & interfaces
└─────┬───────┘
      │
      ▼
┌─────────────┐     ┌───────────┐
│ Implementer  │ ◄── │ UX Agent  │
└─────┬───────┘     └───────────┘
      │
      ▼
┌─────────────┐
│   Tester     │ → writes & runs tests
└─────┬───────┘
      │
      ▼
┌─────────────┐
│  Reviewer    │ → approves or requests changes
└─────┬───────┘
      │
      ▼
┌─────────────┐
│   DevOps     │ → builds, signs, distributes
└─────────────┘
```

## Decision Log

| Date | Decision | Agent | Rationale |
|------|----------|-------|-----------|
| 2026-02-23 | SwiftUI + SPM for native macOS menu bar app | Architect | Lightest footprint, native feel |
| 2026-02-23 | Claude API via direct HTTP (no SDK) | Architect | Minimize dependencies, full control |
| 2026-02-23 | soffes/HotKey for global shortcut | Architect | Battle-tested, simpler than raw CGEvent tap |
| 2026-02-23 | AXUIElement for text selection | Architect | Standard macOS accessibility API |
| 2026-02-23 | Keychain for API keys | Architect | Security — never plaintext on disk |
| 2026-02-23 | @Observable over ObservableObject | Architect | Modern macOS 14+ pattern, less boilerplate |
| 2026-02-23 | Menu bar icon feedback (no overlay) | UX | Less intrusive, more native macOS feel |
| 2026-02-23 | ClipboardService with save/restore | Architect | Preserves user's clipboard during translation |
| 2026-02-23 | TranslationProvider protocol | Architect | Extensible to multiple LLM providers |
| 2026-02-23 | LicenseService as stub | Architect | Prioritize core flow; integrate LemonSqueezy later |
