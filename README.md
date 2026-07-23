# Codex Touch Bar

A standalone macOS menu bar helper that shows projects with active Codex tasks or unread results on a MacBook Pro Touch Bar. It does not require BetterTouchTool and does not modify or re-sign the Codex app.

When Codex is the frontmost app, the Touch Bar shows a horizontally scrollable project strip:

```text
[folder] aviaSurveil360 · 2   [folder] flutter_desktop_up…   [folder] Görevler
```

Tapping a project opens unread results first, then cycles through that project's active tasks and wraps back to the first one.
Projects with an unread Codex result are highlighted in purple with a dot.
The project selected in the active Codex window is highlighted in yellow with a leading arrow.

The right side shows the remaining weekly Codex allowance and provides native Touch Bar popovers for the currently visible task:

- **Weekly limit:** the latest remaining percentage reported by Codex
- **Effort:** Low, Medium, High, Extra High, or Ultra
- **Speed:** Standard or Fast

## Requirements

- A MacBook Pro with a physical Touch Bar
- macOS 13 or later
- The Codex desktop app installed at `/Applications/ChatGPT.app`

This proof of concept has been verified on a MacBook Pro M2 running macOS 26.5.2 and Codex `26.715.52143`.

## Install

1. Download the notarized macOS ZIP from [GitHub Releases](https://github.com/MarlonJD/codex_touchbar/releases).
2. Extract `Codex Touch Bar.app` and move it to `/Applications`.
3. Open the app once.

The app registers itself as a macOS login item on first launch so it starts automatically after future sign-ins. It runs as a menu bar helper and only presents its Touch Bar controls while Codex is frontmost.

## Build and run

```bash
git clone https://github.com/MarlonJD/codex_touchbar.git
cd codex_touchbar
./script/build_and_run.sh --verify
```

Building from source requires Xcode or the Xcode Command Line Tools with Swift 6. The script builds and signs `dist/Codex Touch Bar.app`, then launches it as a menu bar app. It uses the configured Developer ID identity when available and otherwise falls back to an ad-hoc development signature. Use the menu bar icon to disable presentation, refresh task discovery, open Codex, or quit.

The first effort or speed change asks for macOS Accessibility access. Enable **Codex Touch Bar** under **System Settings → Privacy & Security → Accessibility**, return to Codex, and tap the option again. This permission is needed because Codex does not expose a public API for changing these controls in an already-open task.

Optional run modes:

```bash
./script/build_and_run.sh --debug
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

Create a notarized release archive with:

```bash
./script/build_release.sh 0.2.4
```

The release script requires the Developer ID identity and `desktop-updater-notary` Keychain profile. It signs with hardened runtime, submits the archive to Apple, staples the ticket, validates it with Gatekeeper, and writes the final ZIP under `dist/release`.

## How it works

- Reads Codex's local `~/.codex/state_5.sqlite` thread index in read-only mode.
- Checks only task lifecycle fields and weekly rate-limit metadata in recent rollout JSONL files. Prompt and response text is not used.
- Reads Codex's local unread-thread IDs to highlight active projects that need attention.
- Treats a task as active when its latest lifecycle event is `task_started`, unless followed by `task_complete` or `turn_aborted`.
- Groups tasks by their nearest Git repository; Codex scratch directories appear as `Görevler`.
- Opens tasks through the native `codex://threads/<id>` deep link.
- Uses an `NSScrubber` for native horizontal Touch Bar scrolling.
- Changes effort and speed by operating only the matching accessibility controls in the frontmost Codex window. It fails closed when it cannot identify a control or option.

Run the local data-path diagnostic without launching the UI:

```bash
swift run CodexTouchBar --diagnose
```

## Compatibility warning

Apple's public AppKit API only lets the frontmost application provide its own Touch Bar. A separate helper therefore has to invoke the private system-modal Touch Bar selectors at runtime. This makes the app unsuitable for the Mac App Store, and a future macOS update may rename or remove those selectors.

The private bridge is capability-checked at startup and fails closed: if the selectors are unavailable, the menu bar app remains usable and reports that the Touch Bar API is unavailable.

## Development

```bash
swift test --disable-sandbox
```

The package contains:

- `CodexTouchBarCore`: local task discovery, grouping, truncation, and cycling
- `PrivateTouchBar`: a small Objective-C runtime bridge with no compile-time private-framework link
- `CodexTouchBar`: the AppKit menu bar and Touch Bar UI

## License

MIT
