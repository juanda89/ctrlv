# UI Validation

This repo includes a native menu snapshot workflow so the menu can be validated without manual screenshots.

## What it does

- renders the `ctrl+v` menu using the real AppKit/SwiftUI host
- writes PNG snapshots for deterministic debug scenarios
- compares new snapshots against a committed baseline
- generates diff PNGs when the UI drifts

This is intended for layout regressions in the menu popover, especially across macOS appearance changes.

## Requirements

- run outside the Codex sandbox when using the desktop agent
- macOS with AppKit available
- a built debug binary (the scripts build it automatically)

## Single snapshot

Render one scenario/appearance pair:

```bash
./scripts/validate-menu-ui.sh trial light
```

Output:

```text
artifacts/menu-previews/menu-trial-light.png
```

Arguments:

- scenario: `trial`, `active`, `expired`, `invalid`
- appearance: `light`, `dark`

Examples:

```bash
./scripts/validate-menu-ui.sh active dark
./scripts/validate-menu-ui.sh expired light
```

## Baseline workflow

### 1. Create or refresh baseline

Do this only when the menu is visually approved.

```bash
./scripts/validate-menu-ui-matrix.sh --write-baseline
```

This writes baseline PNGs to:

```text
Tests/MenuSnapshots/Baseline/
```

### 2. Validate against baseline

```bash
./scripts/validate-menu-ui-matrix.sh
```

If everything matches, the script exits `0`.

If a snapshot changed, the script exits `1` and writes diff images to:

```text
artifacts/menu-diffs/
```

If a baseline image is missing, the script exits `3`.

## Diff threshold

Default mismatch threshold:

```text
0.003
```

You can override it:

```bash
./scripts/validate-menu-ui-matrix.sh --threshold 0.0015
```

Raise the threshold only for real rendering noise, not for layout changes.

## Debug scenarios

The app includes a debug-only menu fixture so the snapshots do not depend on personal settings.

Current deterministic fixture:

- language: `English`
- tone: `Original`
- provider: `OpenAI`
- API key: fake preview key
- provider status: `OK`
- auto-paste: `on`

License scenarios:

- `trial`
- `active`
- `expired`
- `invalid`

## Recommended workflow before shipping UI changes

1. Change the menu UI.
2. Run:

```bash
./scripts/validate-menu-ui-matrix.sh
```

3. Inspect any diff PNGs in `artifacts/menu-diffs/`.
4. If the new UI is intentional and approved, refresh the baseline:

```bash
./scripts/validate-menu-ui-matrix.sh --write-baseline
```

5. Commit both the UI change and the updated baseline together.

## Notes

- `scripts/build-app.sh` is not part of this flow.
- The snapshot renderer uses the app itself, not a browser or mocked HTML.
- This validates the visible menu state, not translation behavior.
