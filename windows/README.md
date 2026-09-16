# ctrl+v for Windows

- `ControlV.Core` — platform-agnostic port of the Swift `ControlVCore` (models, license state machine, auth/translate/feedback HTTP clients, prompt builder, settings). Builds and tests on any OS: `dotnet test windows/ControlV.sln`.
- `ControlV.Core.Tests` — xUnit tests mirroring the Swift suite.
- `ControlV.App` (Phase 2) — WPF tray app: global hotkeys, UI Automation capture, clipboard paste, popover-like flyout. Windows only.

Same backend, same accounts, same subscription as macOS. See `CLAUDE.md` for the hard-won rules that also apply here.
