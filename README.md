# Latterm

Latterm is a terminal-first macOS fork of iTerm2. The goal is to keep the core terminal, window, tab, session, and rendering stack intact while removing product surface that is outside that focus.

This fork currently removes or de-emphasizes AI, embedded browser, and shell-integration-driven upsell flows. The app presents itself as `Latterm`, and the main bundle identifier is `com.ecnelises.latterm`.

## Status

Latterm is intended to become a clean, long-lived fork rather than a one-off patch set.

- Base UI language is English and remains the default.
- A first-pass Simplified Chinese localization is included in `zh-Hans.lproj`.
- Some internal target names and filenames still use `iTerm2` during the transition, but the shipped app bundle and executable are now `Latterm`.

## What Stays

- Terminal emulation and rendering
- Windows, tabs, panes, and session management
- Profiles, themes, and general preferences
- Existing macOS-native workflow where it still fits the terminal-first direction

## What Is Being Trimmed

- AI-specific onboarding and upsell surfaces
- Embedded browser-specific handling where it is not required for terminal workflows
- Shell integration promotion and adjacent setup flows

This is an active cleanup, not a claim that every related code path is already gone.

## Localization

English does not need a separate translation pack because the Base resources already serve as the default UI language.

Current Chinese coverage includes:

- App display name metadata
- Main menu strings
- About panel strings
- Preference panel strings touched by the fork changes
- Core prompts updated to use localized runtime strings

More strings can be moved into localization tables incrementally without changing the app structure again.

## Building

### Prerequisites

Use the existing setup flow from the upstream project:

```bash
make setup
make paranoid-deps
```

### Development Build

```bash
make Development
```

### Run

```bash
make run
```

`make run` builds the Development configuration and launches `Latterm.app` with the `iterm2-dev` preferences suite.

### Notes

- Code signing is disabled by default for command-line builds.
- `make` now resolves `BUILD_DIR` from the checked-in `iTerm2.xcodeproj`, which avoids the previous failure where `make run` could not determine the build output path.

## Relationship To iTerm2

Latterm is derived from iTerm2 and still uses large parts of its codebase and build system. Upstream architectural documentation, many internal filenames, and some developer tooling still reference iTerm2 because the fork is being narrowed in stages rather than rewritten from scratch.

## License

Like the upstream project, Latterm is distributed under the [GPLv3](LICENSE).
