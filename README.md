# Latterm

Latterm is a terminal-first macOS fork of iTerm2 targeting **macOS 15.0+ on Apple Silicon (`arm64`)**, focused on fast Metal rendering, clean typography, native SwiftUI settings, and zero external submodule or remote package bloat. The shipped app bundle is `Latterm.app` (`com.ecnelises.latterm`).

## Highlights

- **Unified Metal GPU Rendering**: Interactive terminal sessions stay on the Metal renderer even with ASCII and non-ASCII ligatures (`liga`/`clig`/`calt`/stylistic sets, 4+ cell runs, and opaque box-cursor splitting), annotations, or the find bar active.
- **Precision Typography**: Physical-pixel (`0.5pt` Retina) character advance quantization plus ordered per-language and symbol font rules with regional CJK `locl` glyph shaping, relative scale, and baseline offsets.
- **Native SwiftUI Settings & Live TOML Config**: Instant-opening programmatic/SwiftUI Settings (`PreferencePanel.xib` removed) paired with optional Git-friendly declarative configuration at `~/.config/latterm/config.toml` with live hot-reloading and bidirectional export.
- **Lean Dependency Footprint**: **0 git submodules** and **0 remote Swift Package Manager dependencies** — native Swift SIXEL decoding, OpenSSH-backed SCP/config resolution, native expression parsing, and streamlined AppleScript automation.
- **Bilingual UI**: English base UI with comprehensive Simplified Chinese (`zh-Hans`) localization across menus, Settings, and dialogs.

## What Was Removed

- AI chat, LLM providers, inline completions, and Claude Code onboarding/hooks
- Embedded web browser profiles, WebKit previews, and adblock/extension stacks
- Shell-integration script injection, installers, Captured Output, and persistent Core Data command history (terminal-native `OSC 7` and `OSC 133` marks remain first-class)
- Companion iOS app (`iTerm2 Buddy`) and the Python WebSocket/Protobuf RPC runtime

## Building

### Prerequisites

Official builds require Apple Silicon (`arm64`) and macOS 15.0 or later with Xcode installed:

```bash
make setup
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
tools/release_latterm.sh 26.11.10
```

The final zip and SHA-256 file are written under `Build/Releases/<version>/`.
Release versions use `YY.M.patch`: the two-digit year, the calendar month
without a leading zero, and a monthly release counter beginning at `0`.
Latterm does not use iTerm2's update feeds; install new releases explicitly.

## Relationship To iTerm2

Latterm is derived from iTerm2 and still uses large parts of its codebase and build system. Upstream architectural documentation, many internal filenames, and some developer tooling still reference iTerm2 because the fork is being narrowed in stages rather than rewritten from scratch.

## License

Like the upstream project, Latterm is distributed under the [GPLv3](LICENSE).
