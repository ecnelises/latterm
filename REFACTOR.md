# Terminal-First Refactor Plan

This is a living plan for turning this repository into a simpler, modern macOS terminal fork.

It is intentionally subtractive:

- Keep the terminal core.
- Remove browser, AI, and shell integration features.
- Simplify product surface area before attempting large rewrites.
- Migrate surviving app-level code toward Swift after the optional subsystems are gone.
- Remove git submodules as their owning features disappear, with the end goal of a submodule-free fork.

This file is a local planning document. Do not assume it belongs in a release commit unless the user explicitly asks for that.

## Current Status

### 2026-04-14 Phase 1 Progress

- Added a terminal-first feature gate and used it to shut off browser, AI, shell integration, and onboarding entry points at the app surface.
- Removed browser menu exposure at runtime and made browser URL opens fall back to `NSWorkspace` instead of creating browser sessions.
- Removed AI menu/chat entry points at runtime and hid the AI preferences tab when terminal-first mode is enabled.
- Disabled shell integration injection, installer/update prompts, and preference/profile controls that advertise shell integration.
- Reworded remaining shell-integration help surfaces so they stop offering installation and instead report that the fork no longer supports those features.
- Removed the shell integration injection code path from `PTYSession` and remote SSH setup in `Conductor`.
- Deleted `ShellIntegrationInjection.swift` and `Bundle+ShellIntegration.swift` from the target and removed the last installer-window cleanup hook from `PTYTextView`.
- Deleted the legacy shell integration installer UI slice from the repo and target (`iTermShellIntegration*` window/controller/panel/root-view files and XIB).
- Removed the “Install Shell Integration” app tip so the UI stops teaching a feature that this fork no longer intends to keep.
- Deleted the standalone `iTermAI/` project (unreferenced by the main app target) and the standalone `iTermBrowserPlugin/` project (also unreferenced by the main app target), pruning two dead leaf modules.

### 2026-04-15 Phase 2 Progress

- Deleted `sources/Browser/**` and `sources/PTYSession+Browser.swift`, then removed the stale project references that still pointed at those files.
- Kept `sources/ToolWebView.*` and `sources/iTermWebViewWrapperViewController.*` because they are shared helpers still used by non-browser toolbelt/status surfaces.
- Replaced browser-only runtime hooks with terminal-first compatibility shims where non-browser code still referenced browser types or selectors.
- Removed the remaining compile-time dependencies on browser metadata, browser-session find/search plumbing, and browser-only profile/detail lookups.
- Landed the browser-removal slice in local commit `cab7f0cfe` (`Remove browser session support`).
- A local `Development` build now succeeds again after the browser-removal cleanup, so the old `WebExtensionsFramework` blocker is no longer the active state of this worktree.

### 2026-04-16 Browser Audit

- Browser session creation and the main browser UI entry points are no longer the active path in the terminal-first fork, but the browser subsystem is not fully removed yet.
- Remaining browser-specific work still includes profile-type UI and defaults, browser triggers, gateway/plugin plumbing, browser-specific branches in `PTYSession` and `SessionView`, and browser-only onboarding/help copy.
- The profile general pane no longer carries browser-plugin install/reveal/locate controls or the controller logic that polled browser-plugin state for those buttons.
- The profile general pane also no longer exposes browser-only editing controls for profile type switching or initial browser URL.
- Profile preferences now treat browser profiles as terminal-only for enclosure visibility, trigger editing mode, and onboarding copy instead of switching into browser-specific preference UI.
- Terminal-first builds now stop loading raw browser dynamic profiles, stop minting a browser default-profile fallback, and downgrade surviving stored browser profiles to ordinary terminal launch/list behavior instead of preserving browser-specific icons or URL command handling.
- The static main menu no longer defines the old `Web` browser-navigation submenu, so those browser-only commands are gone even before responder-chain cleanup.

### 2026-04-15 Phase 3 Starter Slice

- Removed the Claude Code watcher/onboarding pair (`sources/ClaudeWatcher.swift`, `sources/ClaudeCodeOnboarding.swift`) and the app-delegate hooks that started or showed them.
- This intentionally trims an isolated AI onboarding surface first, leaving the chat stack, gatekeeper, and provider plumbing for later slices.

### 2026-04-16 Phase 3 Build Recovery

- Removed the remaining AI/chat/LLM source entries from the main app target so the terminal-first fork stops compiling dead provider and chat UI files during the current slice.
- Replaced the surviving AI-only call sites in `PTYSession`, `PTYTextView`, the status-bar composer, preferences, migration helpers, and the toolbelt with terminal-first no-op or disabled behavior instead of leaving broken references behind.
- Fixed Gemini-introduced structural breakage while doing that cleanup, including duplicate `@end` blocks, duplicated protocol declarations, and a truncated `PTYSession.m` tail section.
- Kept the surviving entry points shape-compatible where that reduced churn, for example by leaving natural-language-query selectors in place but routing them to terminal-first disabled behavior.

### 2026-04-16 Phase 3 Surface Cleanup

- Removed the startup-time OpenAI key migration hook now that terminal-first builds never enable AI features.
- Deleted AI-specific menu-tip registrations and old Tip of the Day entries so the app stops advertising AI chat, AI command writing, and Codecierge from user-facing help surfaces.
- Reworded the remaining Composer and Auto Composer tips to describe their surviving terminal-first behavior instead of mentioning AI suggestions.
- Removed AI menu icon mappings from `MainMenuMangler` to keep the menu-decoration layer aligned with the shrinking AI surface.
- Updated `README.md` to stop listing AI chat, browser profiles, and shell integration as current headline features of the fork.
- Deleted the remaining AI menu items from `Interfaces/MainMenu.xib` so those commands no longer exist in the static menu definition.
- Removed the AI prompt help markdown resource and replaced its settings help action with a terminal-first disabled message instead of loading AI-specific help content.
- Deleted the matching `PTYTextView+ARC` menu-validation and action handlers for the removed Edit-menu AI commands so the responder chain no longer carries dead menu-only code.
- Deleted the old Tip of the Day entry that still promoted browser profiles as an available feature.

### 2026-05-18 Master Rebase And Claude Cleanup

- Rebased the terminal-first branch onto `master` and resolved the file moves that landed there (`sources/Browser/**`, `sources/ShellIntegration/**`, `sources/ShellIntegrationInstaller/**`, `sources/AITerm/**`, and `sources/ClaudeCode/**`).
- Deleted the remaining AI/chat source tree that had been reintroduced by the rebase, keeping only `sources/AITerm/RemoteCommand.swift` as a temporary compatibility type for surviving terminal-control remote command handlers.
- Removed the newly added Claude Code integration menu controller, health monitor, foreground-job upsell controller, peer settings controller, and Claude-specific workgroup template, then removed their Xcode target references and stale user-default accessors.
- Removed the browser-plugin finder source and target references now that the standalone browser plugin project and browser profile UI are gone.
- Kept the general Coding Agent + Diff + Code Review workgroup preset because it is independent of Claude Code onboarding after the cleanup.
- Preserved master’s `make run` process-activation behavior while switching it to the `Latterm.app` bundle/executable variables.
- Deleted the bundled shell-integration scripts, bash/fish shell-integration loaders, the generated utilities tarball, and the generator script that refreshed them from `submodules/iTerm2-shell-integration`.
- Removed the static “Install Shell Integration” menu item, its responder-chain handlers, shell-history “Install Now” prompt, Tip of the Day entries that advertised shell/SSH integration features, and compatibility-command error text that still told users to install shell integration.
- Removed the bundled `it2ssh` helpers, stopped packaging `conductor.sh`, disabled the `it2ssh`/`SendConductor` escape path under terminal-first mode, and removed `submodules/iTerm2-shell-integration`.
- Recovered the post-rebase build by deleting stale AI/browser compatibility hooks that were reintroduced without their owning types: browser gateway checks, inline chat/session selector registration, AI availability probing, and stale `iTermProcess.h` bridging imports.
- Kept only the small shared types still needed by surviving non-AI code (`Cancellation` and `CompletionItem`) and reduced `RemoteCommand.swift` to a temporary terminal-control compatibility island without LLM safety-check dependencies.
- Updated MIME lookup code to use `UniformTypeIdentifiers` instead of a missing generated MIME table, and fixed the localization script to compile the moved `sources/MainMenu/MainMenu.xib`.
- Tightened the zh-Hans localization build phase so it no longer tries to delete root `MainMenu` resources owned by Xcode’s own resource phases, which restores sandboxed `Deployment` builds.
- Cleared the local code warnings exposed by `Deployment` builds in terminal layout, Metal, Open Quickly, session restart, app startup, and color-map helper code.

### 2026-05-29 Browser Trigger And AI Harness Pruning

- Removed the browser-only trigger classes (`BrowserTrigger`, reader-mode/highlight/hyperlink/reload/inject-JavaScript triggers, and browser workgroup enter/exit triggers) from source and the app target.
- Kept terminal trigger loading intact while making the now-unreachable browser trigger class list empty.
- Deleted the temporary `RemoteCommand.swift` AI tool-call compatibility island and removed the matching `PTYSession` remote-command executor state.
- Removed unused AI state/annotation and AI suggestion shims from `PTYSession.swift`, leaving the existing disabled explain-output responder shape for remaining ObjC call sites.
- Deleted the AI live harness, stale AI/browser ModernTests, refusal fixtures, and `tools/run_ai_live.sh`, then updated `CLAUDE.md` and `tools/run_tests.expect` so they no longer point at the removed live harness.
- Moved the shared `Cancellation` utility from `sources/AITerm` to `sources/Infrastructure`, then removed the empty `AITerm` project group.
- Removed the browser-only `load_url` scripting method, Python API wrapper, docs example, manual test scripts, and local browser page-saver fixture resources.
- Removed `submodules/adblock-rust` and stale project header-search paths now that browser support no longer uses it.
- Removed the browser-mode AI prompt variants from settings defaults and the disabled AI prompt picker so old browser tool references stop surviving as configurable presets.
- Removed dead AI model/API/permission defaults and the unused AI chat session indicators; the hidden AI preferences XIB outlets remain temporarily so nib loading stays safe until the tab is structurally deleted.
- Removed unused AI/Codecierge/LLM and browser adblock/proxy/plugin-hint Advanced Settings entries after confirming they had no live callers.
- Removed the dead Claude Code status-tool nagging offer and its private notification path.
- Removed the shell-integration upgrade-notification path, its generated latest-version table, and the obsolete General preference row; `ShellIntegrationVersion` now only records the detected shell for surviving terminal metadata.
- Removed the browser-profile and in-app-link browser Advanced Settings toggles now that terminal-first mode statically disables browser sessions.
- Removed the standalone `WebExtensionsFramework` local Swift package, its Xcode package/product references, and the now-unused browser-extension profile keys.
- Removed the disabled onboarding/what’s-new window path plus stale onboarding and AI menu-tip image assets.

### 2026-07-18 Shell Injection Compatibility Pruning

- Removed the no-op local shell-integration injection wrapper so terminal jobs now launch directly with their computed environment and arguments.
- Removed the obsolete automatic shell-integration profile key, hidden profile preference controls, enablement logic, default value, and XIB objects.
- Removed Conductor’s `shouldInjectShellIntegration` state and its redundant modified-environment/modified-command fields; the surviving SSH path now uses the original environment and parsed command directly.
- Removed the disabled `it2ssh` and `SendConductor` KVP dispatch path, its VT100/screen delegate methods, and the `PTYSession` implementation that still tried to load the already-deleted `conductor.sh`.
- Removed the input-queue state used only while sending that deleted helper payload, while retaining Conductor hook handling, Framer operation, restoration, and remote-command support.
- Audited `SwiftyMarkdown` before considering submodule removal and confirmed it remains a live dependency of Clippings, Portholes, and shared attributed-string formatting, so it must stay for now.

### 2026-07-18 Captured Output Removal

- Removed the shell-integration-dependent `CaptureTrigger` from the app trigger picker, Objective-C implementation, and Python API.
- Deleted the Captured Output model, invisible interval-tree mark, Toolbelt view, menu-tip asset, Tip of the Day entries, warning preferences, notifications, and coprocess activation path.
- Removed the associated VT100 KVP command, terminal/screen delegate methods, command-mark storage and serialization, deserialization fix-up, and clear-count state.
- Updated ModernTests, legacy Objective-C tests, PerformanceTests, and the Python trigger fixture so no test target implements or exercises the removed protocol surface.
- Kept old profile and arrangement loading fail-soft through the existing generic decoders: unknown trigger classes return no trigger, unknown interval-tree classes are skipped, and the removed command-mark dictionary field is ignored.
- Audited submodules and third-party dependencies for Captured Output ownership and found no dependency that became removable with this slice.

### 2026-08-20 Post-Rebase Test And Asset Pruning

- Deleted AI/chat/orchestration ModernTests and their cassette, refusal, and terminal-safety fixtures that had been reintroduced without their owning production types.
- Removed obsolete AI documentation, test harness scripts, menu-tip image resources, and stale Xcode resource references.
- Updated the surviving Companion envelope forward-compatibility tests to cover only the terminal-control protocol and stopped compiling package-owned legacy chat wire vectors into ModernTests.
- Updated Conductor tests for the shell-integration state already removed from production code.
- Repaired every test target's `TEST_HOST` setting to point at `Latterm.app` so `build-for-testing` and `test` compile the test bundle instead of treating it as its own host executable.
- Refreshed the app icon prompt from a green dollar sign to a Lacold Air Blue hash while preserving the existing icon layouts, canvas sizes, and release-channel variants.
- Audited the remaining submodules after this cleanup; none is owned solely by the deleted tests, fixtures, assets, or documentation, so no additional submodule is safe to remove in this slice.

### 2026-08-21 AI Composer Compatibility Pruning

- Removed the hidden AI controls, warning, and orphaned icon asset from the large Composer, along with the natural-language query route through status-bar delegates.
- Removed the disabled Explain Output and natural-language-query compatibility selectors from `PTYSession` and `PTYTextView`.
- Removed the orphaned AI secure preference, no-op migration hook, stale tip filters, and now-redundant runtime menu cleanup.
- Audited the remaining submodules; none is owned by this Composer compatibility slice, so no submodule became safe to remove.

### 2026-08-21 User-Facing Latterm Branding

- Replaced remaining macOS-app branding in alerts, settings descriptions, tips, menu titles, authorization prompts, default filenames, and bug-report links with `Latterm` project equivalents.
- Preserved compatibility identifiers and wire names such as `com.googlecode.iterm2`, `iterm2:`, `~/.iterm2`, the Python `iterm2` package, public menu identifiers, and terminal protocol reports.
- Left the Companion app name and protocol branding for a separate coordinated rename so the Mac app, iPhone app, relay, bundle identifiers, and migration behavior can change together.
- Audited submodules and confirmed this copy-only branding slice does not make any dependency removable.

### 2026-08-21 Browser Session Compatibility Removal

- Deleted the always-false `PTYSession.isBrowserSession` and `SessionView.isBrowser` state, the empty browser view-controller facade, and browser-only branches across session lifecycle, rendering, find, key handling, window menus, Toolbelt, AppleScript, and the Python API server.
- Collapsed terminal startup onto one `startProgram` entry point and removed the legacy browser arguments that every surviving caller supplied as `NO` and `nil`.
- Removed the browser password-manager window and its duplicate data-source graph while preserving the terminal Keychain service, external-provider selection key, 1Password tag, LastPass group, and adapter protocol behavior.
- Removed the dead browser-only text-view font configuration and Metal unavailability reason.
- Audited submodules and confirmed this compatibility removal did not make any dependency removable.

### 2026-08-22 Browser Profile And Web Preferences Removal

- Removed the browser profile enum case, default-profile selection, icons, launch behavior, menu handling, bulk-copy category, and terminal/browser filtering from the surviving profile model and profile UI.
- Deleted the Web profile settings controller and structurally removed its tab, controls, outlets, and project references from `PreferencePanel.xib` and the Xcode project.
- Preserved fail-soft upgrades for saved browser profiles: static profiles are converted to login-shell terminal profiles and their browser-only serialized keys are discarded, while browser dynamic profiles continue to be ignored.
- Removed browser-only font zoom, initial-URL, window-size, context-menu, paste-special, workgroup-detail, and main-menu compatibility paths that were kept alive by the obsolete profile type.
- Collapsed trigger editing and evaluation onto the terminal-only model, removed the browser match types and content-regex serialization, and deleted unreferenced browser global-search and script-history compatibility objects.
- Audited the remaining submodules and confirmed this profile/settings slice used only app-owned model and AppKit code, so it did not make another submodule safe to remove.

### 2026-08-22 Persistent Shell History Removal

- Defined the surviving semantic-terminal boundary: retain OSC 133 prompt/command marks, OSC 7 and working-directory state, command/output selection, folding, navigation, restoration, and screen/file completion.
- Removed the cross-session Core Data command-history and recent-directory database, generated managed objects, model, controller/additions layer, and the now-unused `CoreData.framework` project dependency.
- Deleted the Command History and Recent Directories toolbelt panels and popups, automatic command-history completion, large-composer history suggestions, menu/API identifiers, help/tip copy, and persistence-only delegate callbacks.
- Retained the bounded per-session command list used by Open Quickly and session restoration; it no longer feeds or writes a global history database.
- Updated directory-tracker tests to assert the retained state behavior and repaired stale terminal-font tests that still called browser-only constructors.
- Audited all 17 remaining submodules and confirmed this slice used only app-owned code plus the system Core Data framework, so no submodule became removable.

### 2026-08-23 Redundant libsixel Artifact Cleanup

- Kept the universal `ThirdParty/libsixel/lib/libsixel.a` and public header used by the sandboxed SIXEL decoder and terminal capability reporting.
- Removed checked-in architecture staging trees, install tools, pkg-config metadata, shell completions, man pages, libtool metadata, and the redundant per-architecture archive copied beside the universal library.
- Ignored the x86 staging prefix so a future dependency rebuild does not reintroduce generated install outputs into version control.
- Retained the `libsixel` submodule because SIXEL parsing and image decoding remain terminal-core features; restored its checkout to the security-fixed revision recorded by the parent repository.

### 2026-08-28 Terminal-First Feature Gate Removal

- Removed the temporary `TerminalFirstFeatures` switch now that this fork permanently ships the terminal-first product surface.
- Collapsed Tip of the Day and menu-tip filtering onto their terminal-first behavior instead of retaining unreachable upstream-product branches.
- Removed the disabled debug menu-icon audit and the unreachable `it2ssh` login-shell wrapper; SSH profiles continue to launch directly with the system `ssh` command.
- Confirmed that no source or project references remain for the deleted feature gate or bundled `it2ssh` path.

### 2026-08-29 Upstream Review Through 206cb5df9

- Reviewed all 357 official iTerm2 commits from `57535cd90fa8d16405d664adea831651d503610d` (`v20260731-nightly`) through `206cb5df9f58d55e68a119f93d2173d48f47d9a6` (`v20260828-nightly`), using `v3.7.0beta9`, `v3.7.0beta10`, and `v3.7.0beta11` as release boundaries.
- Ported the terminal-first-compatible security check that authenticates the peer before accepting a restored mono-server socket (`1260814ac`).
- Ported CSI/SGR parameter-boundary fixes and their regression tests (`2729db2a2` plus follow-ups through `d8d7e3979`), dark-mode DSR request handling (`c0f79a64f`), Kitty Caps Lock reporting (`597c42574`), and the Python `PromptState.FINISHED` wire value (`3063f7e46`).
- Corrected the stale CSI parser test inventory so DECSCL, which has been supported since 2024, is tested as supported instead of making the parser suite fail before reaching the new boundary cases.
- Ported the frame-canonicalizer window-leak fix (`6a281f3f9`), per-token autorelease pools for bounded terminal repaint memory (`6bdd9953f`), Metal smooth-blink cursor compositing (`368a48dfe`), and format-string safety fixes (`f436dec38`).
- Deliberately skipped AI/model/chat, browser, shell-integration, Companion, Workgroups, Tab Groups, Kitty drag-and-drop, and uv Python migration changes because they conflict with the terminal-first scope or require separate product decisions.
- Deferred larger but relevant candidates to focused follow-up slices: tmux focus/geometry fixes (`918fc2762`, `6bf0b1426`, `2f4e6740f`, `f8bb3771f`), URL detection (`0da24d685`, `071dd60aa`), Hangul composition (`1b6b3ccb6`), Advanced Paste (`5164130b2`), and terminal/window rendering performance (`14c75a3c6`, `46d7e066e`, `6947f5902`, `89b533af0`, `a9e55316e`).
- Audited dependency changes in the range and did not restore any removed submodule or accept upstream's regenerated binary dependency artifacts.

### 2026-08-29 XCTest Host Alignment

- Aligned the shared `iTerm2Tests` scheme with its existing `Latterm.app` `TEST_HOST`: build, launch, and profile actions now select the real `iTerm2`/`Latterm.app` target instead of the obsolete `iTerm2Tests.app` runner target.
- Disabled Xcode's Development debug-dylib layout for `Latterm.app` so hosted XCTest bundles can link the stable `Contents/MacOS/Latterm` executable path without a prebuild workaround.
- Confirmed the legacy `iTerm2Tests.app` target is no longer needed by the shared XCTest scheme, but retained it because it remains the custom reflection-based runner for AppleScript tests that cannot resolve their test-app path under XCTest.
- Audited submodules; this scheme/build-setting-only slice changes no dependency ownership.

### 2026-08-29 Maximized Pane State Repair

- Ported upstream issue 12992's coupled-state repair (`31ea32275`) so synthetic-session swaps, session removal, tab-content replacement, and tmux layout rebuilds preserve the maximized tab invariant.
- Replaced raw teardown assertions with crash-reporting assertions and a recovery path that rebuilds the split tree from the saved arrangement when the root subview count is already corrupt.
- Audited submodules; this terminal view state-management fix uses no dependency changes.

### 2026-08-29 Missing Working Directory Recovery

- Ported the unavailable-working-directory recovery and tilde-expansion follow-up (`45e0ed47c` and `5f0c03c0f`) so restored local sessions fall back to the home directory instead of closing when their saved directory no longer exists.
- Limited the local filesystem check to new local launches, preserving remote SSH paths, server connections, and partial attachments, and report the fallback with a one-time terminal banner.
- Made the `posix_spawn` working-directory action best effort as a second defense against a directory disappearing immediately before process creation.
- Audited submodules; session launch recovery uses no dependency changes.

### 2026-08-29 Regex Visualization Removal

- Removed the optional regular-expression railroad-diagram popovers from Trigger and Smart Selection editing while retaining regex matching, editing, playground testing, and syntax help.
- Deleted the WebKit/SVG visualization implementation, its checked-in Rust dylib and header, Xcode link/copy/search-path entries, and dependency build recipes.
- Removed `submodules/railroad_dsl`, reducing the repository from twelve git submodules to eleven.

### Recent Verification

- The two Smart Selection-focused `iTermTextExtractorTest` cases pass on 2026-08-29 after removing regex visualization; the full class still has unrelated user-default-sensitive word-selection expectations.
- `xcrun ibtool` compiles `PreferencePanel.xib` without document errors or warnings on 2026-08-29 after removing the Smart Selection visualization button; pre-existing layout notices remain.
- `tools/build.sh` passes on 2026-08-29 with the regex visualization sources, dylib, build rules, and `railroad_dsl` submodule removed.
- `tools/run_tests.expect ModernTests/iTermSessionRestorationTests` passes all 3 arrangement/profile restoration tests on 2026-08-29 after the unavailable-working-directory recovery.
- `tools/build.sh` passes on 2026-08-29 after porting the local launch fallback and `posix_spawn` race defense.
- `tools/run_tests.expect ModernTests/iTermPTYTabRecursiveRestoreSplittersTests` passes all 10 split-tree reconstruction tests on 2026-08-29 after the maximized-pane state repair.
- `tools/build.sh` passes on 2026-08-29 after porting the maximized-pane teardown recovery.
- A direct `xcodebuild test -project iTerm2.xcodeproj -scheme iTerm2Tests -only-testing:iTerm2XCTests/VT100CSIParserTest` passes all 38 selected tests on 2026-08-29 without a separate app build or `test-without-building` workaround.
- `tools/build.sh` passes on 2026-08-29 after aligning the XCTest scheme and disabling the Development debug-dylib layout.
- `tools/build.sh` passes on 2026-08-29 after the selected upstream security, terminal parsing, rendering, memory, lifecycle, and logging fixes were ported.
- `VT100CSIParserTest` covers the eight new CSI/SGR parameter-boundary regressions added during the upstream review.
- `tools/build.sh` passes on 2026-08-28 after removing the terminal-first feature gate and its unreachable branches.
- `make zip UNIVERSAL=1` passes on 2026-08-23 and produces an unsigned universal Deployment package at `Build/Deployment/Latterm-3_7_20260823.zip`; both the app executable and SIXEL sandbox worker contain arm64 and x86_64 slices, and `unzip -t` reports no errors.
- Development builds of the `iTerm2` and `ModernTests` schemes pass with `-jobs 2` on 2026-08-23, using derived data at `/tmp/iTerm2-dd-libsixel-clean` after redundant libsixel artifact cleanup.
- `xcodebuild -quiet -project iTerm2.xcodeproj -scheme iTerm2 -configuration Development -destination 'platform=macOS' -skipPackagePluginValidation CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO ARCHS='arm64' ONLY_ACTIVE_ARCH=YES -derivedDataPath /tmp/iTerm2-derived-phase2 build` passes on 2026-04-15 after the phase2 browser-session cleanup.
- `xcodebuild -quiet -project iTerm2.xcodeproj -scheme iTerm2 -configuration Development -destination 'platform=macOS' -skipPackagePluginValidation CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO ARCHS='arm64' ONLY_ACTIVE_ARCH=YES -derivedDataPath /tmp/iTerm2-derived-phase3 build` passes on 2026-04-16 after the phase3 AI-removal build-recovery cleanup.
- `xcodebuild -list -project iTerm2.xcodeproj` passes on 2026-05-18 after the Claude/browser-plugin cleanup and shell-integration resource pruning.
- `make paranoid-deps` passes on 2026-05-18 after resetting the clean `SwiftyMarkdown` submodule checkout and allowing Homebrew `gawk` plus its `gettext`, `readline`, `mpfr`, and `gmp` dynamic-library dependencies in `deps.sb`. It refreshed `last-xcode-version` to Xcode 26.5. The command also regenerated local native dependency binaries; those generated framework/archive artifacts were left unstaged pending a separate dependency-artifact decision.
- `xcodebuild -project iTerm2.xcodeproj -scheme iTerm2 -configuration Development -destination 'platform=macOS' -skipPackagePluginValidation CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO ARCHS='arm64' ONLY_ACTIVE_ARCH=YES -derivedDataPath /tmp/iTerm2-dd-terminal-first build` passes on 2026-05-18 after the `make paranoid-deps` recovery and stale AI/browser/session-selector cleanup.
- `tools/build.sh Deployment` passes on 2026-05-19 after the zh-Hans localization build phase was narrowed to generated localized resources and local code warnings were cleared. The remaining log warning is Xcode’s `appintentsmetadataprocessor` metadata-skip message for the absent AppIntents dependency.
- `xcodebuild -project iTerm2.xcodeproj -scheme iTerm2 -configuration Development -destination 'platform=macOS' -skipPackagePluginValidation CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO ARCHS='arm64' ONLY_ACTIVE_ARCH=YES -derivedDataPath /tmp/iTerm2-dd-terminal-first-prune build` passes on 2026-05-29 after browser-trigger and `RemoteCommand` pruning.
- `xcodebuild -project iTerm2.xcodeproj -scheme ModernTests -configuration Development -destination 'platform=macOS' -skipPackagePluginValidation CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO ARCHS='arm64' ONLY_ACTIVE_ARCH=YES -derivedDataPath /tmp/iTerm2-dd-modern-prune build` passes on 2026-05-29 after deleting AI/browser ModernTests and the AI live harness.
- `xcodebuild -project iTerm2.xcodeproj -scheme iTerm2 -configuration Development -destination 'platform=macOS' -skipPackagePluginValidation CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO ARCHS='arm64' ONLY_ACTIVE_ARCH=YES -derivedDataPath /tmp/iTerm2-dd-terminal-first-api-prune build` passes on 2026-05-29 after removing the browser-only `load_url` API, fixture resources, and `adblock-rust` submodule references.
- `xcodebuild -project iTerm2.xcodeproj -scheme ModernTests -configuration Development -destination 'platform=macOS' -skipPackagePluginValidation CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO ARCHS='arm64' ONLY_ACTIVE_ARCH=YES -derivedDataPath /tmp/iTerm2-dd-modern-api-prune build` passes on 2026-05-29 after the same browser API/resource pruning.
- `xcodebuild -project iTerm2.xcodeproj -scheme iTerm2 -configuration Development -destination 'platform=macOS' -skipPackagePluginValidation CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO ARCHS='arm64' ONLY_ACTIVE_ARCH=YES -derivedDataPath /tmp/iTerm2-dd-terminal-first-prompt-prune build` passes on 2026-05-29 after removing the browser-mode AI prompt presets from settings code and the disabled AI prompt picker.
- `xcrun ibtool --errors --warnings --notices --compile /tmp/Latterm-PreferencePanel.nib sources/Settings/PreferencePanel.xib` passes on 2026-07-18 after structurally removing the hidden shell-integration controls. The XIB retains its pre-existing layout notices but reports no document errors or warnings.
- Development builds of both the `iTerm2` and `ModernTests` schemes pass on 2026-07-18 with derived data at `/tmp/iTerm2-dd-shell-integration-prune` after shell-injection and SendConductor compatibility pruning. The full rebuild still reports the existing `CoreParse.framework` non-portable include-path warning.
- Development builds of the `iTerm2`, `ModernTests`, `iTerm2Tests`, and `PerformanceTests` schemes pass on 2026-07-18 with derived data at `/tmp/iTerm2-dd-terminal-first` after Captured Output removal.
- `tools/run_tests.expect ModernTests/CompanionEnvelopeForwardCompatTests` passes on 2026-08-20, compiling the complete ModernTests target and executing all 8 selected terminal-control protocol tests without failures.
- `tools/run_tests.expect ModernTests/ConductorIT2CommandTests` passes on 2026-08-20 with all 13 selected Conductor restoration and terminal-control tests succeeding.
- `tools/build.sh` passes on 2026-08-20 after the post-rebase AI test, fixture, asset, documentation, and Xcode-reference cleanup.
- `xcrun ibtool --errors --warnings --notices --compile /tmp/Latterm-LargeComposer.nib sources/StatusBar/Components/iTermStatusBarLargeComposerViewController.xib` reports no document errors, warnings, or notices on 2026-08-21 after removing the AI controls.
- `tools/build.sh` and the `ModernTests` scheme build pass on 2026-08-21 after pruning the remaining AI Composer compatibility path.
- `ibtool` compiles the main menu and preference panel without document errors or warnings on 2026-08-21 after the user-facing Latterm branding pass; the preference panel retains its pre-existing layout notices.
- `tools/build.sh` passes on 2026-08-21 after the user-facing branding and bug-report link updates.
- `tools/build.sh` passes on 2026-08-21 after removing browser-session compatibility and duplicate password-manager paths.
- The `ModernTests` scheme build passes on 2026-08-21 with derived data at `/tmp/iTerm2-dd-browser-shell` after the same cleanup.
- Development builds of the `iTerm2` and `ModernTests` schemes pass with Xcode task concurrency limited to two jobs on 2026-08-22, using derived data at `/tmp/iTerm2-dd-profile-prune` after browser profile and Web preferences removal.
- `ibtool` compiles `PreferencePanel.xib`, `BulkCopyProfilePreferences.xib`, and `MainMenu.xib` without document errors or warnings on 2026-08-22; the first two retain only their pre-existing layout notices.
- Development builds of the `iTerm2` and `ModernTests` schemes pass with `-jobs 2` on 2026-08-22, using derived data at `/tmp/iTerm2-dd-shell-history-prune` after persistent shell-history removal.
- Selected ModernTests pass under the scheme's ASan test variant on 2026-08-22: all 46 `iTermSessionDirectoryTrackerTests` and all 6 `PromptMarkBaselineTests` succeed.
- `ibtool` compiles `MainMenu.xib` without document errors, warnings, or notices and `PreferencePanel.xib` without document errors or warnings after the history UI removal; the preference panel retains its pre-existing layout notices.
- Development builds of the `iTerm2` and `ModernTests` schemes pass with `-jobs 2` on 2026-08-22, using derived data at `/tmp/iTerm2-dd-dependency-prune` after redundant `fmdb`, `BTree`, and `MultiCursor` submodules plus stale SwiftyMarkdown package references were removed.

## Refactor Direction

The target product is a terminal-first app:

- Terminal emulator, sessions, tabs, panes, rendering, profiles, and basic preferences stay.
- Browser sessions are removed.
- AI chat, AI agents, and model integrations are removed.
- Shell injection, installers, persistence, and shell-integration-only UX are removed; semantic terminal metadata such as OSC 7 and OSC 133 remains part of the terminal core.
- Old compatibility constraints should be relaxed so the surviving code can use a more modern macOS baseline and Swift-first patterns.

## Current Repository Observations

The removal scope is real, not hypothetical:

- The browser and AI source trees and their standalone projects are gone, and the surviving profile model no longer represents browser sessions.
- Shell-integration installation and injection code is gone, and the former `sources/ShellIntegration/**` persistence model plus its Core Data dependency are now removed. OSC 7/133 parsing and session-local semantic state remain.
- `sources/PTYSession.m` remains a major coupling point across terminal lifecycle, scripting, terminal control, triggers, and UI.
- The source tree remains heavily Objective-C weighted: 500 Swift files vs 1,696 Objective-C/C-family headers and implementations among 2,299 files under `sources/` as of 2026-08-22.
- Eleven submodules remain. Redundant `fmdb`, `BTree`, and `MultiCursor` checkouts plus the optional regex-visualization dependency are gone; further removals require separate audits of surviving SSH, rendering, parsing, Markdown, syntax-highlighting, Companion, updating, and build-tool paths.

Because of that, a rewrite-first approach is the wrong move. The practical order is delete first, then simplify, then migrate.

## Preserve First

These areas are the product core and should be stabilized before major rewrites:

- Window and tab model: `sources/iTermController.m`, `sources/PseudoTerminal.m`, `sources/PTYTab.*`
- Session lifecycle and process execution: `sources/PTYSession.*`, `sources/PTYTask.*`
- Terminal emulation: `sources/VT100*`
- Rendering: `sources/PTYTextView.*`, `sources/Metal/**`

These are high-risk systems. Avoid rewriting them until the optional product surfaces are removed and the compile graph is smaller.

## Remove Early

### Browser

Primary removal candidates:

- `sources/Browser/**`
- `sources/PTYSession+Browser.swift`
- Browser branches inside `sources/PTYSession.m`
- `sources/iTermBaseWKWebView.*`
- `iTermBrowserPlugin/`
- Browser-specific preferences, onboarding, history, bookmarks, and profile creation flows

Notes:

- `sources/ToolWebView.*` and `sources/iTermWebViewWrapperViewController.*` were initially browser-adjacent but are still shared by surviving non-browser UI. Do not delete them until those remaining consumers are migrated or removed.

Expected cleanup areas:

- Browser session restoration keys in `PTYSession`
- Browser-specific profile modes and menu items
- Browser-related tests, assets, onboarding pages, and menu tips

### AI

Primary removal candidates:

- `iTermAI/`
- `sources/Chat*.swift`
- `sources/AI*.swift`
- Remaining AI preference/default keys and XIB controls that still expose model/API-key configuration
- `sources/LegacyOpenAI.swift`
- `sources/CompletionsOpenAI.swift`
- `sources/O1OpenAI.swift`
- `sources/ResponsesAPI*.swift`
- `sources/AIPluginClient.swift`
- AI-specific menu tips and preferences

Expected cleanup areas:

- Chat window/menu entry points
- AI permission flows linked to terminal or browser sessions
- Preferences and defaults related to model selection, API keys, or automatic sending

Notes:

- The chat stack, AI completion, Codecierge surface, and shared gate/client layer have been removed from the app target during the phase 3 cleanup.
- The temporary `RemoteCommand.swift` compatibility island is gone as of the 2026-05-29 pruning slice; remaining SSH `runRemoteCommand` call sites are separate terminal-control plumbing, not AI tool-call code.
- Claude Code onboarding, menu, health monitoring, foreground-job upsell, and Claude-specific workgroup template code are gone; future workgroup cleanup should focus on generic terminal workflows, not Claude-specific migrations.

### Shell Integration

Primary removal candidates:

- `Resources/shell_integration/**` (removed from the bundle; the directory may disappear once no tracked files remain)
- `sources/ShellIntegrationInjection.swift`
- `sources/Bundle+ShellIntegration.swift`
- `sources/iTermShellIntegration*`
- `sources/iTermShellPromptTrigger.*`
- `sources/iTermShellHistoryController.*`

Likely follow-on cleanup:

- Shell-integration-specific notices and version checks in `PTYSession`
- Trigger descriptions and warnings that depend on shell integration
- Profile or preferences UI that installs, updates, or advertises shell integration

Retained boundary:

- Keep OSC 133 prompt/command marks and return codes because command/output selection, folding, mark navigation, triggers, and restoration consume them directly.
- Keep OSC 7, working-directory polling, session-local directories/hosts, and filename/path completion.
- Keep the bounded session-local command list used by Open Quickly, but do not restore a global persistence database or history UI.

### Review Later, Not First

These may also be good candidates for removal or heavy simplification, but they should be evaluated after the three big deletions above:

- AppleScript and scripting surfaces: `sources/*Scripting*`, `iTerm2.sdef`
- Python/script runtime helpers: `sources/iTermPython*`, `sources/iTermAPIScriptLauncher.*`
- WebSocket/API surfaces: `proto/api.proto`, `sources/iTermAPIServer.*`, `tests/websocket/`
- Toolbelt subsystems that are only valuable because of removed features

## Design Rules For The Fork

- Subtract before rewriting.
- Keep the app buildable after every phase.
- Do not mix a major feature deletion with a large-scale Swift migration in the same slice.
- Do not start by renaming the app or targets. Keep those changes until after the product surface is smaller.
- Do not rewrite `VT100*` or `Metal/*` early unless the user asks for a terminal-core redesign specifically.
- When a subsystem is removed, audit and remove its now-unused submodules instead of carrying dead external dependencies forward.

## Submodule Strategy

The end state should have no git submodules.

Rules:

- Do not delete a submodule before its compile-time references, runtime loaders, resources, and docs are removed.
- Prefer feature-owned removals: delete the submodule in the same phase as the feature that required it, or immediately after that phase lands cleanly.
- Start with optional feature submodules before touching infrastructure-heavy ones.

Safe-first targets:

- `submodules/SwiftyMarkdown` once AI/chat and markdown-only surfaces are gone, if no surviving UI still depends on it

High-risk later targets:

- `submodules/NMSSH`, `submodules/libssh2`, `submodules/openssl`
- `submodules/libsixel`
- `submodules/libgit2`
- `submodules/CoreParse`

## Recommended Phases

### Phase 0: Baseline and Dependency Map

Goal: know what still boots before deleting anything.

- Build the current app with the existing instructions in `CLAUDE.md`.
- Smoke-test terminal creation, split panes, tabs, copy/paste, profile switching, and search.
- Identify browser, AI, and shell-integration entry points in menus, profiles, onboarding, defaults, and window restoration.
- Map the largest coupling hotspots, especially in `PTYSession`, `PseudoTerminal`, and profile/preferences code.

Deliverable:

- A short dependency note for each removal area and a verified baseline build.

### Phase 1: Turn Features Off At The Surface

Goal: make unsupported features unreachable before deleting implementation.

- Remove or hide browser, AI, and shell integration entry points from menus, settings, toolbars, onboarding, and default profiles.
- Make unsupported profile/session types fail fast instead of partially initializing.
- Stop creating new browser sessions or AI windows from UI actions.
- Stop advertising shell integration installation or update flows.

Deliverable:

- Product surface looks terminal-only even if dead code still exists underneath.

### Phase 2: Remove Browser Session Support

Goal: collapse the app back to terminal sessions only.

- Delete `sources/Browser/**` and browser helper classes after UI entry points are gone.
- Remove browser-specific branches from `PTYSession`, `PseudoTerminal`, and related session restoration code.
- Remove browser profile creation and browser-only preference keys.
- Remove browser plugin integration and browser-related assets/tests.
- Keep only the minimal compatibility shims needed to compile non-browser callers while phase3/phase4 continue deleting adjacent code.

Success criteria:

- The app no longer creates, restores, or references browser sessions anywhere.

### Phase 3: Remove AI

Goal: eliminate chat, agent, and model plumbing.

- Delete chat windows, AI controllers, model clients, request/response types, and AI-specific preferences.
- Remove AI-linked session permission flows.
- Remove AI menu items, toolbars, tips, onboarding content, and warnings.
- Remove the separate `iTermAI/` project if it is no longer referenced.

Recommended first slices:

1. Audit preferences/defaults for AI vendor/API-key keys that are now legacy migration baggage.
2. Keep pruning static menu, tip, and localization strings that mention removed AI, Claude Code, or browser functionality.
3. Remove any remaining target-only references to stale AI/browser tests or resources as they surface during full test target builds.

Success criteria:

- No UI path, target, or preference remains for AI features.

### Phase 4: Remove Shell Integration

Goal: stop patching the shell environment and prune dependent UX.

- Remove shell integration injection from session startup.
- Delete installers, panels, resources, and update prompts.
- Remove shell-integration-specific triggers, warnings, and helper controllers when their value disappears without shell integration.
- Re-evaluate semantic history and command history features: keep only what still makes sense without shell-side hooks.
- Continue shrinking Conductor/SSH integration code now that the `it2ssh` and `conductor.sh` resource path is gone.

Success criteria:

- Launching a session no longer injects shell integration and the app has no shell-integration install/update UX.
- `submodules/iTerm2-shell-integration` remains absent and no enabled project/resource/runtime path depends on its helpers.

### Phase 5: Simplify Product Surface

Goal: reduce complexity that existed to support removed features.

- Shrink preferences panes and advanced settings.
- Remove empty or low-value toolbelt features.
- Simplify onboarding and profile creation.
- Remove menu tips, help pages, and assets tied to removed subsystems.
- Remove submodules that became unnecessary in Phases 2 through 4 and update the project file accordingly.

Success criteria:

- The app reads like a focused terminal instead of a feature platform.

### Phase 6: Swift-First App Layer Migration

Goal: migrate surviving application/UI logic toward Swift without destabilizing the terminal core.

Recommended order:

- Window controllers, preference controllers, onboarding, and small managers
- Session-adjacent coordinators that can be split out of `PTYSession`
- App services and state containers
- High-value Objective-C categories that should become explicit Swift types or protocols

Avoid early rewrites of:

- `VT100*`
- `PTYTextView`
- `PTYTask`
- Metal renderers

Reason:

- Those areas are performance-sensitive and deeply coupled. They should be isolated first, not translated blindly.

### Phase 7: Raise The Platform Baseline

Goal: use a modern macOS target deliberately instead of carrying old compatibility baggage.

Recommendation:

- Decide an explicit new baseline early. `macOS 15` is the cleanest target for aggressive modernization.
- If that is too aggressive for distribution goals, `macOS 14` is the fallback.

Then:

- Remove obsolete availability code and compatibility shims.
- Replace legacy patterns with modern AppKit/Swift approaches where the surviving product benefits.
- Revisit dependencies that only exist for old platform support.

### Phase 8: Rebrand And Rename

Do this after the product is smaller and stable:

- Rename targets, bundle identifiers, assets, and product strings.
- Systematically replace remaining `iTerm2` project-level names in
  `iTerm2.xcodeproj`, including project name, scheme names, target names,
  product references, build-setting names, copied helper paths, and script
  assumptions. Do this as a dedicated slice so project-file churn does not
  obscure feature-removal diffs.
- Update documentation and packaging.
- Remove leftover iTerm2 branding that is no longer accurate for the fork.

Success criteria:

- The shipped app, project, schemes, primary targets, helper bundle names,
  archive paths, and packaging scripts consistently use `Latterm`.
- Remaining `iTerm2` names are either user-facing compatibility names that
  intentionally preserve old behavior, or comments documenting upstream
  provenance.

### Phase 9: Release Signing And Notarization

The current command-line build is contributor-friendly: `make Deployment`
and `tools/build.sh Deployment` disable signing by default. The upstream
release scripts still assume iTerm2’s original Developer ID, Apple account,
team ID, app name, bundle path, and `build/` output layout.

Before shipping public binaries:

- Decide the Latterm Developer ID Application certificate, Apple team ID,
  notarytool credential profile, and signing key ownership.
- Replace upstream release-script identity assumptions, including
  `Developer ID Application: GEORGE NACHMAN (H7V7XYVQ7D)`,
  `apple@georgester.com`, `H7V7XYVQ7D`, `iTerm2.app`, `iTerm.app`, and
  lower-case `build/` paths.
- Add an explicit signed build target or script for Latterm, separate from
  the unsigned contributor build.
- Notarize with `xcrun notarytool submit --wait`, staple the result, and
  verify with `codesign --verify`, `codesign -dv --verbose=4`, and
  `spctl -a -vvv -t exec`.
- Update Sparkle/appcast packaging only after the app naming and signing
  chain are stable.

Success criteria:

- A clean machine can produce an unsigned local build without credentials.
- A release machine with credentials can produce a signed, notarized,
  stapled Latterm archive without any iTerm2 account or path assumptions.

## Immediate Execution Slice

The first practical batch should be narrow and keep the app compiling:

1. Add a terminal-first scope section to agent docs and keep this roadmap current.
2. Remove browser, AI, and shell integration entry points from menus/preferences/onboarding without deleting deep implementation yet.
3. Delete the easiest leaf modules next: separate AI clients/projects and shell integration installers that are no longer reachable.
4. Only then start cutting browser session branches out of `PTYSession` and related model code.

## What Not To Do

- Do not start with a full app rewrite in Swift.
- Do not start by translating `PTYSession.m` line-for-line into Swift.
- Do not delete terminal-core code and optional product code in the same large patch.
- Do not bump deployment targets and remove three subsystems in one commit-sized change.

## Working Rule For Agents

When working on this fork:

- Follow `CLAUDE.md` first.
- Use this file to choose the next smallest coherent slice.
- Prefer changes that reduce coupling in `PTYSession`, profile management, and top-level UI entry points.
