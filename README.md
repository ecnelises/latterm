# Latterm

Latterm is a terminal-first macOS fork of iTerm2. The goal is to keep the core terminal, window, tab, session, and rendering stack intact while removing product surface that is outside that focus.

This fork currently removes or de-emphasizes AI, embedded browser, and shell-integration-driven upsell flows. The app presents itself as `Latterm`, and the main bundle identifier is `com.ecnelises.latterm`.

## Status

Latterm is intended to become a clean, long-lived fork rather than a one-off patch set.

- Base UI language is English and remains the default.
- Simplified Chinese localization covers menus, Settings, and common dialogs in `zh-Hans.lproj`.
- Some internal target names and filenames still use `iTerm2` during the transition, but the shipped app bundle and executable are now `Latterm`. Renaming the Xcode project, schemes, targets, product references, helper paths, and packaging scripts is tracked as a dedicated refactor phase so project-file churn stays separate from feature removal.

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

Official builds require Apple silicon and macOS 12.4 or later.

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

`make run` builds the Development configuration and launches `Latterm.app` with the `Latterm-Development` preferences suite when run from this checkout. Preferences and Application Support data stay separate from the installed release.

### Notes

- Code signing is disabled by default for command-line builds.
- Build products are written to the repository’s `Build/` directory by default. Set `BUILD_DIR=/absolute/path` to use another directory.
- Contributor builds remain unsigned by default. Official releases use the
  `R7ZJJDMW42` Developer ID team, the `com.ecnelises.latterm` bundle identity,
  and a local notarytool keychain profile; no Apple credentials are stored in
  the repository.

### Signed Release

Install a “Developer ID Application” certificate for team `R7ZJJDMW42`, then
store App Store Connect notarization credentials once:

```bash
xcrun notarytool store-credentials latterm-notary \
  --apple-id "YOUR_APPLE_ID" \
  --team-id R7ZJJDMW42
```

Build, verify, notarize, staple, and package an exact version with:

```bash
tools/release_latterm.sh 26.10.1
```

The final zip and SHA-256 file are written under `Build/Releases/<version>/`.
Release versions use `YY.M.patch`: the two-digit year, the calendar month
without a leading zero, and a monthly release counter beginning at `0`.
Latterm does not use iTerm2's update feeds; install new releases explicitly.

## Relationship To iTerm2

Latterm is derived from iTerm2 and still uses large parts of its codebase and build system. Upstream architectural documentation, many internal filenames, and some developer tooling still reference iTerm2 because the fork is being narrowed in stages rather than rewritten from scratch.

## License

Like the upstream project, Latterm is distributed under the [GPLv3](LICENSE).
