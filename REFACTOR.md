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
- Audited `SwiftyMarkdown` before considering submodule removal and confirmed it was then a live dependency of Clippings, Portholes, and shared attributed-string formatting; those consumers were later migrated together to Foundation's CommonMark parser.

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

### 2026-08-29 Porthole Highlighter Removal

- Replaced the single `Highlightr` consumer with app-owned rendering: Markdown and JSON keep their specialized renderers, while other content uses the active terminal font and colors.
- Reduced the Porthole language menu to its three truthful rendering modes and map restored legacy source-language selections to plain text.
- Removed the custom highlighting CSS settings and resources, the checked-in framework, Xcode link/copy/resource references, dependency build recipe, and signing helper reference.
- Removed `submodules/Highlightr`, reducing the repository from eleven git submodules to ten without removing Portholes.

### 2026-08-29 Foundation Markdown Migration

- Replaced the three live `SwiftyMarkdown` integration points with one app-owned renderer built on Foundation's CommonMark parser.
- Preserved headings, emphasis, links, code fonts and wrapping, lists, block quotes, front-matter removal, dynamic colors, and consumer-specific heading scales across Portholes, Clippings, and shared help/announcement rendering.
- Corrected inline-code generation to use CommonMark backtick delimiters long enough to contain literal backticks.
- Removed the checked-in framework and header, Xcode link/copy/group references, dependency build and cleanup recipes, signing helper, license entry, and `submodules/SwiftyMarkdown`, reducing the repository from ten git submodules to nine.

### 2026-08-29 Relay Operations Checkout Removal

- Confirmed `submodules/iterm2-companion-relay` was not an application, Companion project, package, build, or runtime input; its only repository reference was a two-line Cloudflare log-tail helper.
- Removed the uninitialized relay deployment gitlink and its obsolete helper while retaining all app-owned Companion protocol, transport, pairing, push-relay, and client code.
- Reduced the repository from nine git submodules to eight without changing the deployed relay contract or client feature surface.

### 2026-08-29 Application Update Boundary

- Added an app-owned software-update service and driver seam so launch, restart preservation, menu actions, update-window filtering, and feed configuration no longer depend directly on Sparkle APIs.
- Replaced the XIB-instantiated `SUUpdater` object with lazy service ownership while retaining automatic checks, manual checks, restart notification handling, version comparison, feed selection, and the legacy archive app-name override.
- Confined application-update Sparkle APIs to one adapter implementation. The Sparkle submodule now remains only as the source of the updater framework and can be replaced without changing application consumers.

### 2026-08-29 App-Owned Version Comparison

- Replaced the last three non-updater Sparkle consumers in Python runtime discovery, dependency editing, and optional-component compatibility checks with an app-owned comparator.
- Preserved dotted-number, prerelease, and build-number ordering while making arbitrarily long numeric components compare without integer overflow.
- Reduced direct Sparkle source usage to the software-update adapter; dependency-source migration no longer risks coupling API/runtime download logic to the updater framework.

### 2026-08-29 Official Sparkle 2 Dependency

- Audited the old Sparkle fork and confirmed its alternate application-name patch is obsolete because Sparkle 2 falls back to bundle-identifier matching.
- Replaced the checked-in framework and git submodule with the official Sparkle 2.9.6 Swift package, and migrated the adapter from the global `SUUpdater` singleton to an owned `SPUStandardUpdaterController`.
- Moved dynamic appcast selection to the Sparkle 2 updater delegate, cleared the deprecated stored feed override, and retained EdDSA verification, automatic/manual checks, and restart signaling.
- Removed the old framework link/copy references, dependency recipes, signing-project reference, and Sparkle gitlink, reducing the repository from eight git submodules to seven.

### 2026-09-03 Redundant CoreParse Checkout Removal

- Confirmed the tracked `ThirdParty/CoreParse` source tree is complete, carries the local compatibility fixes, and independently builds the framework consumed by the app.
- Switched the dependency rebuild target and Xcode source-browser group from `submodules/CoreParse` to that app-owned source tree.
- Removed the duplicate CoreParse gitlink, reducing the repository from seven git submodules to six without changing the expression-parser runtime boundary.

### 2026-09-03 System Git Migration

- Replaced the embedded libgit2 status, diff, branch, and repository-operation implementation with `/usr/bin/git` machine-readable porcelain and NUL-delimited diff output while preserving the existing `iTermGitState` boundary.
- Removed the libgit2 gitlink, checked-in headers and binary artifacts, dependency recipes, and Xcode link/search settings after confirming no remaining source or runtime references.
- Reduced the repository from six git submodules to five; Git status now fails soft when the system Git command is unavailable.

### 2026-09-03 Obsolete AI Development Artifact Cleanup

- Removed the orphaned AI model-catalog publisher and raw AI wire-log parser after confirming their model catalog, logger, and application consumers were already gone.
- Removed the bundled AI plugin sandbox profile from all resource phases and deleted the unreferenced Claude Code hook model and integration research note.
- Audited the remaining AI-like filenames and retained only historical release notes, terminal behavior fixtures, Companion protocol types, generic command explanation, and live code-review resources.
- This development-artifact cleanup removed no additional submodule; all five remaining submodules still have live terminal, SSH, or Companion owners.

### 2026-09-03 Workgroup Orchestrator Residue Removal

- Removed unused workgroup entry provenance that had been introduced for the deleted AI orchestrator and onboarding paths.
- Removed the unused resolved-member snapshot adapter after confirming no callers remain.
- Preserved trigger, menu, and restoration entry behavior while shortening the public and internal workgroup entry APIs.

### 2026-09-03 Stale Shell Integration Harness Removal

- Removed the opt-in shell-integration live harness and its dedicated pseudo-terminal helper after confirming their runner and bundled shell scripts were already gone.
- The harness previously skipped during ordinary tests and could not succeed when manually enabled because every tested integration script path was absent.
- Preserved terminal-core OSC 133 parser, screen-state, prompt-mark, and session-directory tests.

### 2026-09-03 Tip Compatibility Residue Removal

- Removed the dynamic browser, AI, shell-integration, and SSH-integration string filter after confirming none of those removed tips remain in the static tip dictionary.
- Removed the four still-present but unconditionally blocked tip entries from the dictionary itself, preserving the exact returned tip set without an intermediate filter.
- Removed two unused browser-era WebKit forward declarations and corrected the named-mark notification's stale browser-session comment to describe its live window refresh behavior.

### 2026-09-03 Inline Chat Compatibility Removal

- Removed the disabled Show Inline Chat menu item, menu-icon mapping, responder action, and validation branch.
- Removed the session's unreachable inline-chat ID, visibility, notification, right-gutter relayout, and compatibility toggle state after confirming there are no panel or model consumers.
- Preserved the neighboring Clippings right-gutter feature and its layout notifications.

### 2026-09-03 Orphaned Development Tooling Removal

- Removed the unreferenced Python 2 UKCrashReport-to-plist converter and its sole dependency, the checked-in PLY 3.4 source, example, documentation, and test tree.
- Removed the standalone crash fetch/clustering scripts after confirming they were not part of the build or release flow and depended on a personal Dropbox layout plus the removed AI-development workflow.
- Removed an uncompiled image-popover helper introduced by the deleted AI/browser integration and two empty, unreferenced legacy test shells whose filenames no longer matched their declarations.
- This cleanup removes app-unowned development files only; the five remaining git submodules and all live API, AppleScript, terminal, and crash-reporting runtime code remain unchanged.

### 2026-09-04 Dynamic Web Tool Removal

- Removed Python-script registration of arbitrary Toolbelt web views across the public protobuf schema, API server/helper dispatch, Python SDK and documentation, persistent dynamic-tool registry, application menu refresh path, and WebKit-backed Toolbelt implementation.
- Rebuilt the bundled arm64 `it2` CLI against the reduced schema so its embedded protobuf runtime no longer publishes the removed request, response, or accessors.
- Reserved the retired request and response field number 104 in their protobuf envelopes so it cannot be accidentally reused for an incompatible API operation.
- Removed the obsolete duplicate Python protobuf stub from 2019; the SDK retains its generated in-package type stub as the single source of truth.
- Preserved every built-in Toolbelt tool and the separate WebKit-backed terminal link-preview/status-popover path.

### 2026-09-04 Scripted Status Bar Web Popover Removal

- Removed the status-bar HTML popover's exclusive request and response messages from the public protobuf schema, API server/helper dispatch, Python SDK, reference documentation, and downloadable example, while reserving envelope field number 129.
- Deleted the bundled `iterm2Invoke.js` resource and the WebKit script-message bridge that let arbitrary popover HTML invoke native functions and receive evaluated JavaScript callbacks.
- Reduced the shared WebView factory to the ordinary WKWebView configuration needed by terminal URL previews, removing its script delegate protocol, runtime availability checks, and private Web Inspector preference.
- Preserved script-provided status-bar text, icons, configuration knobs, click callbacks, and unread counts, as well as the terminal URL-preview popover and its external-browser fallback.
- Rebuilt the bundled arm64 `it2` CLI against the reduced schema; no submodule is owned by this app/API surface, so all five live submodules remain unchanged.

### 2026-09-04 Terminal-Only Profile Type Collapse

- Removed the obsolete `ProfileType` option set after browser profiles had already been retired; profile models, filtered lists, settings search, action editors, paste configuration, Toolbelt, and status-bar setup now operate directly on the single surviving terminal profile kind.
- Collapsed terminal-mode enclosure handling onto an always-visible layout group while retaining the independent hidden-control and shared-profile enclosure behavior.
- Removed dynamic Toolbelt constructor and type-capability protocol hooks that no longer had consumers after script-provided web tools were deleted.
- Preserved every built-in Toolbelt panel, terminal action, profile picker, advanced-paste option, and status-bar component; no default or serialized profile key changed.
- Audited the five remaining submodules and confirmed none is owned by this app-level compatibility plumbing.

### 2026-09-04 In-App Browser URL Routing Removal

- Collapsed `NSWorkspace+iTerm` URL opening onto external applications after confirming every in-app-browser capability check was hardcoded false.
- Removed unused browser target, split-pane style, upsell, and source-window parameters across URL actions, semantic history, launch services, terminal mouse handling, application controllers, and Swift callers.
- Deleted the unreachable context-menu and Command-Shift-click URL split-pane actions while preserving command-mark selection and normal Command-click URL opening.
- Preserved configured custom external browsers for HTTP, HTTPS, and FTP, system handlers for file and custom schemes, background activation behavior, URL handler commands, and profile-bound custom schemes.
- Kept fail-soft legacy browser-profile migration separate from runtime URL routing so saved profiles still upgrade safely.
- Audited all five remaining submodules; external URL routing uses only AppKit and app-owned code, so no dependency became removable.

### 2026-09-04 Terminal Metadata UX Cleanup

- Replaced user-facing Shell Integration installation requirements with the actual retained terminal metadata boundaries for prompts, commands, working directories, hosts, and users.
- Reworked user-variable examples to emit `SetUserVar` directly, so the settings help and Python examples no longer depend on removed bundled shell helpers.
- Repaired the Python menu generators for the relocated main-menu XIB and identifier-free menu items, then regenerated the SDK menu API and identifier reference from the current terminal-first menu.
- Preserved OSC 7/133 parsing, prompt marks, command lifecycle state, automatic profile switching, status-bar variables, and prompt-aware paste behavior.
- Audited all five remaining submodules; this UI, documentation, and SDK cleanup does not own any of them.

### 2026-09-04 Terminal Session Compatibility Cleanup

- Removed the browser-era named-mark capability hook now that every live session is a terminal session; menu validation depends directly on whether a current session exists.
- Made the profile-switch helpers return `void` after confirming their browser-type rejection path was gone, and removed the automatic switcher's unreachable “wrong profile type” failure branch.
- Removed the status-bar component's orphaned WebView JavaScript diagnostic callbacks and forwarding methods after the scripted HTML bridge and its delegate protocol had already been deleted.
- Preserved named marks, automatic profile switching, script-provided status text and HTML formatting, and the separate terminal URL-preview WebView.
- Audited the five remaining submodules; these app-owned compatibility seams do not own any dependency.

### 2026-09-04 Obsolete Web Restoration Coordination Removal

- Deleted the session-restoration status protocol and completion notification after confirming their only former consumers were the removed browser and dynamic WebView surfaces.
- Removed the notification-only restoration counter from `PseudoTerminal`; synchronous and asynchronous arrangement restoration retain their load, attachment, decode, window-ordering, timeout, and completion behavior.
- Removed Global Search's empty session traversal, which had previously forced hidden browser WebViews to begin loading before search.
- Removed the protocol sources from the Xcode project while preserving terminal global search, arrangement restoration, and terminal URL previews.
- Audited the five remaining submodules; this app-owned coordination residue does not own any dependency.

### 2026-09-05 Popup Input Compatibility Removal

- Removed the Popup delegate's key-selector interception path after persistent command history and its large-composer popup integration had been deleted; the sole remaining implementation always returned `NO`.
- Simplified popup navigation, deletion, cancellation, selection, and text filtering to execute their existing fallback behavior directly.
- Removed the matching `PTYSession` no-op delegate implementation, two ancient public event methods with no callers, and an unused layer-capability method left behind by an abandoned rendering experiment.
- Preserved autocomplete, paste history, popup filtering, row selection, Composer behavior, and the live session mode handler used by Copy Mode and shortcut navigation.
- Audited the five remaining submodules; this app-owned input-routing cleanup does not own any dependency.

### 2026-09-05 Terminal Delegate Capability Collapse

- Removed the Find driver's browser-specific Enter-key override after terminal sessions became its only delegate; Enter and Shift-Enter continue to follow the existing next/previous search preference.
- Removed the text-view delegate's filled-cursor override after its automatic-command-history consumer was deleted; legacy and Metal rendering now read Focus Follows Mouse state directly.
- Removed `SessionView`'s visibility query after confirming `PTYSession` was its only implementation and had returned `YES` since the protocol was introduced; detached views retain the prior no-redraw behavior through the nullable delegate check.
- Removed the stale disabled-test implementation of the retired cursor delegate method while retaining direct drawing-helper cursor coverage.
- Audited the five remaining submodules; these app-owned delegate seams do not own any dependency.

### 2026-09-05 Python Preference Surface Alignment

- Removed the Python SDK's `AUTO_COMMAND_HISTORY` preference enum after confirming the application setting, menu command, popup, model, and runtime behavior were already gone.
- Corrected `SAVE_PASTE_HISTORY` documentation to describe its surviving paste-history-only behavior and retained the live application preference it controls.
- Removed the stale command-history menu-icon comment and verified every remaining Python `PreferenceKey` value still has an application source, XIB, or test owner.
- Audited removed Captured Output, recent-directory, and command-history terminology across live API and source files; only historical release notes and the truthful named-mark navigation tip remain.
- Audited the five remaining submodules; this SDK/documentation cleanup does not own any dependency.

### 2026-09-05 Disabled PTYTextView Golden Suite Removal

- Deleted the 3,009-line `PTYTextViewTest.m` after confirming its entire contents had remained behind a top-level `#if 0`, so the test target compiled no code from it.
- Deleted all 298 PNGs in its dedicated `tests/Goldens` directory (2.02 MiB) and removed their source, group, build-phase, and resource references from the Xcode project.
- Preserved the active `ModernTests` rendering coverage, including `TerminalRendererTest`, `iTermCharacterSourceTests`, and `iTermRowOutputCacheTests`.
- Audited the five remaining submodules; these disabled test fixtures did not own any dependency.

### 2026-09-05 Process Collection Test Migration

- Migrated the five behavior groups from the wholly disabled Objective-C `iTermProcessCollectionTest` into the active Swift `ModernTests` target.
- Preserved coverage for independent process trees, deepest foreground jobs across branches, trees without foreground jobs, cycle isolation, and nested foreground-job precedence.
- Deleted the old `#if 0` test shell and its Xcode source references after the replacement suite passed.
- Audited the five remaining submodules; this test-only migration does not own any dependency.

### 2026-09-05 Disabled Rendering Diagnostic Cleanup

- Removed the `#if 0` CPU fast-path overlay that drew yellow borders around rendered glyph regions.
- Removed the `#if 0` Metal texture diagnostic that wrote sequential `wtf*.png` dumps into `/tmp`.
- Preserved the live renderer debug-info pipeline and explicit Metal image-dump helper used by active diagnostics.
- Audited the five remaining submodules; these app-owned debug fragments did not own any dependency.

### 2026-09-05 Interval Tree Test Reactivation

- Re-enabled the 14 fast `iTermIntervalTreeTest` cases that had been hidden behind a file-wide `#if 0` despite covering live terminal data structures.
- Updated the test helper to use `Interval`'s current designated initializer instead of mutating its now-read-only bounds.
- Retained the separately guarded 1,000-iteration randomized stress test in its existing disabled state because it is explicitly documented as very slow.
- Audited the five remaining submodules; this test-only reactivation does not own any dependency.

### 2026-09-05 State Restoration Coding Test Migration

- Replaced the wholly disabled 1,669-line `iTermCodingTests.m` suite with active Swift coverage in `ModernTests` and removed its legacy Xcode project entries.
- Added five current-schema graph-table transformer tests covering nested reconstruction, malformed rows, invalid field types, multiple roots, and dangling parents.
- Added four graph-delta array tests covering unchanged-generation skipping, value updates, deletion, and append behavior; the remaining graph encoder, database, recovery, and lazy-loading responsibilities were already covered by active ModernTests suites.
- Exposed `iTermGraphTableTransformer` to the Swift target and completed the test-facing root-node out-parameter nullability contract.
- Confirmed the separately disabled Semantic History questionable-suffix regression still changes raw-action filename semantics; left that behavior untouched for a dedicated compatibility decision.
- Audited the five remaining submodules; this test-only migration does not own any dependency.

### 2026-09-05 Disabled VT100Screen Test Cleanup

- Deleted the 4,810-line `VT100ScreenTest.m` historical suite after confirming its entire 108-test body had remained behind a top-level `#if 0` since 2023 and no longer compiled against the current screen architecture.
- A diagnostic compile reached 124 warnings and the compiler's 20-error limit across retired screen construction, delegate, grid, search-result, and mutable-state APIs; upstream still carries the same disabled shell.
- Confirmed 25 annotation and resize regressions were migrated by name into the active Swift `VT100ScreenTests`, while current `VT100ScreenTests`, `VT100GridTests`, `SearchEngineTests`, and `LineBufferTests` provide 308 active tests across the surviving responsibilities.
- Removed the obsolete file and build references from the legacy XCTest target.
- Audited the five remaining submodules; this test-only cleanup does not own any dependency.

### 2026-09-08 Embedded URL Preview Removal

- Removed the terminal's WebKit-backed HTTP/HTTPS preview popover from Force Click and the selected-text context menu, eliminating the last in-app web-content surface.
- Deleted the dedicated WebView factory and wrapper controller, their project references, the URL-preview context-menu delegate seam, and the now-unused custom WebView user-agent setting.
- Preserved Command-click URL opening, Open Selection as URL, web search, configured external browsers, hover URL text, dictionary lookup, and Quick Look for local files and images.
- Audited the five remaining submodules; this AppKit/WebKit surface did not own any of them, so no submodule became safe to remove.

### 2026-09-21 Finder Services And Bundle Metadata Cleanup

- Rebranded Finder's New Tab Here and New Window Here services across all five build channels and the AppleScript test app, preserving service selectors, accepted pasteboard types, and context requirements.
- Rebranded document type descriptions, URL-handler display names, system permission prompts, network policy descriptions, and remaining Mac/API alerts; added Simplified Chinese Finder service titles.
- Removed obsolete HTML viewer registration, the WebKit-only transport exception, and nonexistent Help Book declarations after embedded browser and preview removal.
- Preserved compatibility schemes, document extensions, resource names, keychain/storage names, public identifiers, and the separately distributed iTerm2 Buddy identity. Project/target/helper naming remains a dedicated Phase 8 slice.
- Audited the five remaining submodules; bundle metadata and app-owned copy do not own any dependency, so none became removable.

### 2026-09-22 Settings Search And Release-Diff Follow-Up

- Prioritized search and settings organization at the user's request: results now carry the live page/section path and application/profile scope, index navigation labels, rank exact keys and visible titles ahead of keyword-only hits, preserve identically keyed settings from different owners, and deduplicate after non-ASCII substring matching. Index snapshots retain document identity without letting later controller traversal mutate the indexed paths.
- Added an explicit no-results row, Return-to-open-first-result and Escape dismissal, guarded empty/tokenless queries and stale selection, and anchored the taller two-line result list below the search field within the display.
- Read the existing `UPSTREAM` cursor (`206cb5df9f58d55e68a119f93d2173d48f47d9a6`) before fetching with `git fetch --no-recurse-submodules upstream master --tags`. The fetched master is `e507018556d4f428548ed176ceb37b014ed62427` (227 intervening commits).
- Checked the official downloads page and actual tag contents: stable `v3.7.2` points to `8f1f5170a423cb73a32be1a2487434f5984d5f24`; advertised test `v3.7.1beta1` points to `85892eb49eef454ee8241f2003b8124cd5154fa8`. Compared beta11→beta12, beta12→3.7.0, test→3.7.1, and test→3.7.2 as content diffs, not as assumed master ancestry. The release branches carry cherry-picked equivalents and release-only changes.
- Release summary: beta12 adds focused RTL/performance fixes and password-manager/Tab Group changes; 3.7.0 stabilizes that line; 3.7.1 adds old-RTL restoration, completion display, URL/tmux/API fixes; 3.7.2 concentrates on crashes, filtering, tmux layout/title behavior, keyboard restoration, and renderer/report synchronization. The test→3.7.2 source diff touches 35 files, including unsupported product surfaces and already-diverged build compatibility code.
- Selected semantic ports (code only, without upstream binary/project/default churn): Actions redraw (`a0f08f179`); missing on-disk dynamic profiles (`49de2b517`); main-screen picker separator (`a9cdabb62`, post-release master); committed searchable-menu selection (`eb2992d96`, post-release master, adapted to the local Swift package); malformed tmux layouts (`268c28405`); legacy RTL metadata decoding (`ee0613322`); Metal main-thread timeout configuration (`769fb4a67`); modifyOtherKeys restoration (`97baa31c4`); interrupted filter refinement (`caf289d41`); tmux title updates without profile reload (`40f30767b`); the MRC missing-directory notice lifetime portion of `0f7e0d6d6`; release-branch retrospective keycode redaction (`8152d9674`); and emoji/UTF-16 URL safety (`583839032`, post-release master).
- Skipped AI/model/chat, browser, shell-integration installation, AI-specific Companion/Workgroups changes, upstream string-catalog replacement, checked-in framework/native binaries, dependency deployment-target changes, signing identity assumptions, and silent default changes. The Settings UI continues to use the fork's navigation and Chinese resources. This slice introduces no submodule references; all five remaining submodules still have independent live owners.
- Deferred relevant follow-ups with explicit dependencies: OSC 4/DSR synchronization (`6e176764d`, `daa957956`) together with livelock coverage (`4915720d4`) and executor scheduling corrections (`e54e01d4c`); mouse-mode notification coalescing (`43bd1e07e`); tmux toolbar geometry (`4f979134d`, plus previously recorded border/focus fixes); API create-tab focus deferral (`ed1dfdea6`); full-screen URL boundary extraction (`04d02ca49`/`b7df732ef`, adapt to the fork's current URL pipeline); RTL rendering/selection chain beginning `98682fc3d`; grid generation and persistence optimization (`a804fab2c`, `14d64bd21`); nonblocking file paste (`32450755c`); and native cell-size/window reports (`4665948ac`, `0c1f56822`). Consider optional prevent-sleep/profile triggers (`27dc3c043`) and bidi paste sanitization (`1f4b1bd9a`, `f3c9345ae`) as separate product slices with explicit settings/default review.
- `UPSTREAM` is intentionally unchanged. This is a release-focused selection with an inventory of the master range, not a completed per-diff classification/verification of every intervening master commit. Do not advance the cursor on the strength of this slice.

### 2026-10-01 Expert Settings Follow-Up

- Put the expert filter, editing instructions, and table into one scrolling document. Recompute its height after filtering and column-width changes, and keep global search targets visible in that document.
- Complete 30 Chinese descriptions missed by the earlier single-line/semicolon-only localization check. Validate multiline definitions, definitions without semicolons, and all category labels.
- Removed ten settings after auditing accessor, setter, literal-key, and indirect warning-key references across tracked source: `hotkeyWindowFloatsAboveOtherWindows`, `searchSuggestURL`, `timeoutForStringEvaluation`, `wordSelectionRegexRadius`, `darkThemeHasBlackTitlebar`, `disableWindowShadowWhenTransparencyPreMojave`, `noSyncNeverRemindPrefsChangesLostForUrl`, `noSyncDontWarnAboutTmuxPause`, `noSyncClearAllBroadcast`, and `companionWakeupCoalesceInterval`. Removed their declarations and Chinese descriptions as well; existing stored preferences are left intact.
- Keep legacy external-instance opening preferences because `newInstanceOpenStyle == -1` still reads them. Settings such as `dismemberScrollView` and `allowTabbarInTitlebarAccessoryBigSur` also still affect rendering/window behavior despite dated descriptions; retiring them needs a separate behavior/default migration, not just deleting their UI.
- The removed settings have no runtime consumers or dependency owners. Audited `.gitmodules`; all five remaining submodules retain separate SSH, SIXEL, or Companion owners, so none can be removed in this slice.
- Verification: Development build passes; four localization checks cover all 454 remaining definitions. The 35-case Settings suite passed 34 cases initially; the sole failure was an old inset-layout assertion, now updated and passing in a focused rerun. Whole-page scrolling, filter shrinkage, last-row search visibility, and typed editing pass. Exported and visually checked the Chinese Expert Settings screenshot. No changed application source emits compiler warnings; Xcode still reports existing stale-output/AppIntents notices and the test host reports existing font-picker resource diagnostics.

### 2026-10-04 External File Opening And Obsolete Shadow Settings

- Replace three deprecated external-file-opening toggles and the raw integer editor with one localized four-choice popup (new window, tab, vertical split, horizontal split). The existing `NewInstanceOpenStyle` values 0–3 retain their meaning, and the effective factory default remains a tab.
- Resolve missing, legacy -1, and out-of-range values through the old keys with their original precedence and defaults. Read compatibility values without automatically writing migrations or modifying synced preference files; observe legacy-key changes so the editor continues to reflect imported preferences.
- Use the resolved style for both launch style and target-window selection. This fixes the case where legacy `OpenFileInNewWindows=YES` forced a new target window even after the user explicitly chose a tab or split with the newer setting.
- Remove `disableWindowShadowWhenTransparencyOnMojave`, its description/declaration, and the single caller/helper confined to pre-macOS-11 execution. The minimum supported macOS 12 already bypassed that code, so supported-system behavior is unchanged.
- No submodule owns these preference or AppKit branches. All five remaining submodules still have independent live consumers.
- Verification: `tools/build.sh Development` passes with only the existing AppIntents metadata notices. Five focused Settings tests pass under ASan, including the legacy-choice/explicit-override matrix, no migration writes on read, popup persistence/default filtering, search, typed editors, and whole-page scrolling. Four localization checks pass, now covering enum option titles as well as all 450 remaining setting definitions. `git diff --check` passes.

### 2026-10-04 Settings Release Hardening

- Audit editable controls across every settings page at 820, 1040, and 1280 points. Propagate legacy form minimum widths to the shared document so disabling inner scrollbars cannot hide controls. Keep responsive profile sections sized to the viewport instead of stretching them to match the widest sibling.
- Verify profile selection, narrow/wide resizing, persistent profile management, global search, and deep-link scrolling. Inspect native Chinese screenshots, including the expert editor, profiles, pointer bindings, and saved layouts.
- Localize runtime pointer-action, button, and gesture labels and the workgroup empty state/help button. Remove the duplicate new-window action key that mislabeled it as a new-tab action; assert unique action-picker display names.
- Guard release-script cleanup until the complete input backup exists. Four offline failure-path tests cover an existing output directory, unavailable signing, and failed builds with or without a pre-existing generated plist.
- No submodule ownership changes; retained SSH, SIXEL, and Companion dependencies remain live. Keep this roadmap out of code commits.
- Verification: all 47 selected ASan tests pass (39 Settings, three preference fast-accessor, five restoration), along with four localization and four release-cleanup checks. The final Development build passes with only the existing AppIntents metadata notice. Native Chinese screenshots confirm translated pointer rows/workgroup guidance, unclipped responsive profile fields, and the expert page. Restarting this run's stale ibtoold helpers resolved local NIB output permission failures without changing project settings.
- Local commits: `682ffe8c2` (settings) and `149f24073` (release cleanup). The final signed 26.10.1 arm64 candidate targets macOS 12.4+, verifies Developer ID/hardened runtime and deep/strict signatures before and after extraction, and contains the final Chinese resources. Artifact: `Build/ReleasePreparation/26.10.1/Latterm-26.10.1-candidate.zip`, SHA-256 `1803001791a48a49fbbdf916dab7d80c1f6b55cbb95dd0ef14f7514cad272dc8`. Source version remains 26.9.2 until a formal release. No push, tag, notarization, or publication performed. This roadmap is the only remaining working-tree change.

### 2026-10-04 Shared Setting Definitions And Quick Navigation

- Add a Swift adapter over the existing 450 expert-setting macro definitions. Editing, localization, type validation, modified-state filtering, defaults, and search use the same definition without changing preference keys or factory defaults.
- Show factory values and saved/legacy/protected sources in name tooltips. Add per-setting reset buttons, including removal of legacy external-file-opening keys; preserve secure getter/setter failure handling and unspecified tri-state values.
- Reuse the Settings search index in Open Quickly. Ordinary queries include settings; `/,` restricts the palette to settings, while `/` retains the existing command tips. Result identity and activation preserve owner, scope, and indexed navigation paths.
- Verification: all 55 selected ASan tests pass (five definition, 42 Settings navigation, three preference fast-accessor, five session restoration), plus four localization checks. Screenshot review caught AppKit's nil-column spanning group headers; repaired them and added an assertion, then passed four focused layout/search/reset checks. Reviewed native Chinese palette results and final Expert Settings page screenshots. The changed application code adds no compiler warnings.
- The earlier signed 26.10.1 preparation artifact predates this refactor and must be rebuilt before release. No public release operations are part of this change. Keep this roadmap local; the release notes are in `docs/notes-3.7.txt`.
- Local commit: `b3aa7560c` (shared definitions, reset, and quick navigation). Final `tools/build.sh Development` passes with only the existing AppIntents metadata notice; `git diff --cached --check` passes. The roadmap is the only remaining working-tree change.

### 2026-10-04 Profile Values And Factory Restore

- Add a Swift profile settings inspector under Other Actions. Reuse bound control metadata, localized search titles, section paths, and existing reveal routing. Search by title, path, or key; filter factory differences; show profile values, sources, bindings, and factory values.
- Centralize factory profile values, preserving preset colors/fonts, Unicode 9 for newly created profiles, and factory badge definitions independent of expert overrides. Resolve runtime transformations consistently for comparison, including the current color variant. Correct the nullable profile getter contract for Swift without changing runtime defaults.
- Restore only independent, directly persisted controls through their existing profile controller. Write the factory value explicitly so removing a key cannot reactivate a global/legacy fallback. Keep bindings and controls requiring custom side effects in their specialized editors. Capture profile GUID and color-key identity; do not redirect restores after a selection change or recreate deleted profiles.
- Verification: the 60-test Settings/expert/accessor/restoration ASan selection passes. After adding the optional-value bridge check and extending profile-identity/deletion coverage, all 14 final affected tests pass (five profile definitions, one inspector flow, three accessors, five restoration). Four localization checks and final Development/Deployment builds pass; native Chinese inspector screenshots are reviewed. Only generated precompiled headers were cleared to recover stale module maps after switching configurations. No warnings are introduced by the changed application code.
- This slice inspects profile values before evaluating session expressions. Comparing divorced sessions with their source profile remains a follow-up; use the existing session override tracking rather than inventing another inheritance model. No dependencies or submodule ownership changed. Keep this roadmap local, and rebuild/sign/notarize the previous release candidate before any public release.

### 2026-11-03 Partial Upstream Master Triage After 3.7.6

- `UPSTREAM` stays at the reviewed 3.7.6 release commit `7ce456b98db38d3f0bafd70ffec87752e69d5d58`. This pass triaged the 600 master commits since the release branch diverged at `5964ff231` by subject and patch applicability; it is not a complete classification, so the cursor was not advanced.
- Ported the x-man-page allowlist hardening (`f29420ae4`), character-width initialization race (`8dc03200e`), removed-tab activation crash guard (`2c8bee4ea`), URL template `+` encoding (`4d907f27d`), delegate-less composer highlighting (`99ccc1b08`), disabled-ligature shaping (`124020064`), cropped Kitty image texture frames (`5f1786330`), kitty keyboard flags across XTMODKEYS (`146b2356e`), bidi partial-copy spacing (`0d919c1e4`), alert text-editing shortcuts (`023d97c2a`), input-method arrow and Tab hand-backs (`7f4ff7397`), and Hide Activity Indicator for progress spinners (`7e862eb49`).
- Skipped as already present or structurally divergent: the detached tmux `select-window` guard (`7f86879da`, already guarded earlier in the method), tmux select-window error tolerance (`db8daf71b`, renames a selector the fork's tests call), and pane unmaximize container sizing (`dcd01a915`, depends on the floating-pane `setNativeRootFrameSize:` refactor).
- Deferred clean candidates for a focused follow-up: Metal layer lock hang (`ec4517e6b`), Caps Lock input-source reports (`beb7cfbff`), hyperlink archive saving (`9f7bda6f8`), and the AppKit title-indexing and refresh-rate performance fixes (`12c882686`, `171e435ff`, `2805bb742`).
- Audited dependency impact: these ports touch only app-owned sources and tests; no submodule is added or becomes removable.

### Recent Verification

- On 2026-11-04, reconciled the stashed roadmap with `046e68195` and `545389446`, retaining both histories and updating 15 master-review dispositions. `tools/build.sh Development` and all 13 localization checks pass. The build emits no compiler warnings; the AppIntents processor only reports skipped metadata extraction because the app has no AppIntents dependency. `UPSTREAM` and the version remain unchanged. This is a documentation reconciliation and build check, with no release operations.

- The 26.9.2 follow-up passes 33 Settings/tmux regressions, the final 29-test Settings suite, three localization checks, and a final Development build. Added narrow/wide light/dark heading checks and reviewed native-window snapshots; fixed Chinese scope-badge text insets. Search result panels now recover their preferred height when moved away from screen edges and reset scrolling for a new query. Commits `55973557c`, `1deecee59`, and `1243b3fc7` are pushed to `origin/clean`; this roadmap stays local. The 26.9.2 arm64 Deployment build is complete and passes deep/strict Developer ID signature verification for team `R7ZJJDMW42`; its version, bundle identity, and macOS 12.4 minimum are verified. The signed pre-notarization zip is in `Build/ReleasePreparation/26.9.2/`. On 2026-09-23, Apple notarization `31372b24-3971-4cca-8f39-290ee20c5f21` was accepted. The stapled final ZIP passes extraction, deep/strict signature, ticket, and Gatekeeper verification. Published https://github.com/ecnelises/latterm/releases/tag/v26.9.2 as the latest release with the ZIP and SHA-256 file; both GitHub asset digests match the local files. Tag `v26.9.2` resolves to `1243b3fc7571c5cb7e053ea3770c7f63c87d2321`. Final artifacts are under `Build/Releases/26.9.2/`.

- On 2026-09-22 `tools/build.sh Development` passes after the settings-search changes and 13 selected upstream fixes. The ASan ModernTests selection passes all 124 tests across Settings navigation, menu-item shortcut editing, tmux layout parsing, line-block restoration, URL encoding, filter refinement, and session restoration. A final five-test search rerun passes after adding Expert Settings categories and clearing stale highlights. All three localization checks and `git diff --check` pass; changed files emit no compiler warnings. Exported and inspected the XCTest search-result layout attachment. Existing CNoise vendor warnings and AppIntents metadata notices remain. No submodule or Xcode project dependency changes were needed.

- On 2026-09-21 all six application plist variants pass semantic checks for the Finder/bundle cleanup; service routing, document extensions, and URL schemes remain compatible. Localization/property-list syntax and `git diff --check` pass. With user authorization, updated `last-xcode-version` to Xcode 27.0 (27A266a) and verified the existing native dependencies through a successful Development build without rebuilding or cleaning them. Built-app metadata and Chinese Finder-service resources also pass inspection. The build reports existing CNoise vendor warnings and AppIntents metadata notices; no changed application source emits compiler warnings.

- `tools/build.sh Development` passes on 2026-09-08 after removing the embedded URL preview and its WebKit wrapper.
- `tools/run_tests.expect ModernTests/VT100ScreenTests ModernTests/VT100GridTests ModernTests/SearchEngineTests ModernTests/LineBufferTests` passes all 308 active terminal-core tests under the ModernTests ASan variant on 2026-09-05.
- An arm64 Development `build-for-testing` of the `iTerm2Tests` scheme compiles and links `iTerm2XCTests.xctest` on 2026-09-05 after deleting the disabled `VT100ScreenTest` suite.
- `tools/build.sh Development` passes on 2026-09-05 after removing the disabled `VT100ScreenTest` suite.
- `tools/run_tests.expect ModernTests/GraphTableTransformerTests ModernTests/GraphDeltaArrayTests` passes all 9 migrated state-restoration coding tests under the ModernTests ASan variant on 2026-09-05.
- The surrounding graph database, delta encoder, recovery, and migrated coding suites pass all 27 selected ModernTests cases on 2026-09-05.
- The complete lazy-loading, schema-migration, legacy-database, and provider regression selection passes all 39 tests on 2026-09-05.
- `tools/build.sh Development` passes on 2026-09-05 after migrating the disabled state-restoration coding suite.
- A selected arm64 Development run of `iTerm2XCTests/IntervalTreeTest` passes all 14 re-enabled interval overlap, ordering, balancing, and removal tests on 2026-09-05.
- `tools/build.sh Development` passes on 2026-09-05 after removing the disabled CPU and Metal rendering diagnostics.
- `tools/run_tests.expect ModernTests/ProcessCollectionTests` passes all 5 migrated process-tree tests on 2026-09-05.
- An arm64 Development `build-for-testing` of the `iTerm2Tests` scheme compiles and links `iTerm2XCTests.xctest` on 2026-09-05 after deleting the disabled `PTYTextViewTest` suite and its dedicated golden images.
- `tools/build.sh Development` passes on 2026-09-05 after aligning the Python preference surface and removing its stale main-menu comment.
- Python bytecode compilation and an AST enum-presence check pass on 2026-09-05 after removing the dead command-history preference; every remaining SDK preference value matches a live application key.
- `tools/build.sh Development` passes on 2026-09-05 after collapsing browser-search, automatic-history cursor, and constant SessionView delegate capabilities.
- `tools/build.sh Development` passes on 2026-09-05 after removing obsolete Popup input interception and unused `PTYSession` event/layer hooks.
- `tools/build.sh Development` passes on 2026-09-04 after deleting obsolete WebView restoration coordination and its Xcode project entries.
- `tools/build.sh Development` passes on 2026-09-04 after removing terminal-session capability shims and orphaned status-bar WebView callbacks.
- `tools/build.sh Development` passes on 2026-09-04 after the terminal-metadata wording and SDK generation cleanup.
- `ibtool` compiles all three changed XIBs without document errors or warnings on 2026-09-04; only pre-existing layout notices remain.
- Python bytecode compilation, XML validation, generator idempotency checks, and a direct `SetUserVar` escape-sequence smoke test pass on 2026-09-04. The Python pytest suite could not start because `pytest` is not installed in the local Python 3.14 environment.
- `tools/run_tests.expect ModernTests/NSURLUserSuppliedStringTests ModernTests/ExtendURLSearchResultsTests` passes all 9 selected URL parsing and boundary-extension tests on 2026-09-04.
- `tools/build.sh Development` passes on 2026-09-04 after removing obsolete in-app browser URL routing and split-pane compatibility paths.
- A fresh-DerivedData arm64 Development build of the `ModernTests` scheme passes on 2026-09-04 after collapsing the terminal-only profile compatibility axis.
- All 31 `ModernTests/iTermLayoutCalculatorTest` cases pass on 2026-09-04, including the Toolbelt frame and visibility coverage.
- `tools/build.sh` passes on 2026-09-04 after collapsing terminal-only profile-type and dynamic Toolbelt compatibility plumbing.
- `ibtool` compiles `PreferencePanel.xib` without document errors or warnings on 2026-09-04 after simplifying enclosure visibility; its pre-existing layout notices remain.
- `tools/build.sh` and an isolated arm64 Development build of the `ModernTests` scheme pass on 2026-09-04 after removing scripted status-bar HTML popovers and the WebView RPC injection bridge.
- A fresh-DerivedData arm64 Development app build passes on 2026-09-04, and its `Latterm.app` contains neither the removed JavaScript resource nor a stale bundled CLI.
- Python bytecode compilation and a protobuf descriptor smoke test pass on 2026-09-04, confirming that field 129 and its request/response messages are retired.
- `make it2cli` succeeds and all 39 `it2coreTests` pass on 2026-09-04 after rebuilding the bundled CLI against the reduced status-bar protocol.
- `tools/build.sh` passes on 2026-09-04 after removing dynamic web Toolbelt tools and regenerating the Objective-C and Python protobuf bindings.
- An isolated arm64 Development build of the `ModernTests` scheme passes on 2026-09-04 after the same API, Toolbelt, SDK, documentation, and project cleanup.
- Python bytecode compilation and a protobuf descriptor smoke test pass on 2026-09-04, confirming that field 104 is retired and no register-tool messages remain.
- `make it2cli` succeeds and all 39 `it2coreTests` pass on 2026-09-04 after rebuilding the bundled CLI against the reduced protocol.
- An isolated arm64 Development build of the `iTerm2Tests` scheme succeeds on 2026-09-03 after removing the empty legacy test shells and orphaned development tooling.
- `tools/build.sh` passes on 2026-09-03 after removing the obsolete crash-analysis scripts, vendored PLY tree, and uncompiled image-popover helper.
- `xcrun ibtool --compile /tmp/Latterm-MainMenu.nib sources/MainMenu/MainMenu.xib` completes without output on 2026-09-03 after deleting the disabled inline-chat menu item.
- `tools/build.sh` passes on 2026-09-03 after removing the inline-chat session state, notification, responder action, validation branch, and menu metadata.
- `tools/build.sh` passes on 2026-09-03 after replacing the dynamic removed-feature tip filter with the final static tip set and deleting stale browser declarations.
- `tools/run_tests.expect ModernTests/PromptMarkBaselineTests` rebuilds the ModernTests target and passes all 6 retained OSC 133 prompt-mark tests on 2026-09-03 after deleting the stale live harness.
- `tools/build.sh` passes on 2026-09-03 after removing obsolete workgroup provenance and member-snapshot plumbing.
- `tools/run_tests.expect ModernTests/WorkgroupEntryTests` passes all 55 workgroup entry tests on 2026-09-03 after shortening the entry API.
- `tools/build.sh` passes on 2026-09-03 after removing the obsolete AI development artifacts and all `ai-plugin.sb` resource references; Xcode also removes the stale resource from the Development app bundle.
- `tools/build.sh` passes on 2026-09-03 after replacing libgit2 with system Git and deleting its checked-in artifacts, link settings, and submodule.
- `tools/run_tests.expect ModernTests/iTermGitClientTests` passes all 32 repository-status, diff, branch, nested-path, operation-state, and ahead/behind tests on 2026-09-03 after removing libgit2.
- `tools/build.sh` passes on 2026-09-03 after switching CoreParse dependency rebuilds and source browsing to the tracked source tree and removing the duplicate submodule.
- `tools/run_tests.expect ModernTests/iTermExpressionParserTests` passes all 124 expression parsing and evaluation tests on 2026-09-03 after the CoreParse checkout cleanup.
- A standalone arm64 Release build of `ThirdParty/CoreParse/CoreParse.xcodeproj` succeeds on 2026-09-03 before switching the dependency rebuild path.
- `tools/run_tests.expect ModernTests/iTermSoftwareUpdateServiceTests` passes all 3 update-operation, dynamic-feed, and restart-state tests on 2026-08-29.
- `tools/build.sh` passes on 2026-08-29 and the built app embeds and links official `Sparkle.framework` 2.9.6.
- `tools/run_tests.expect ModernTests/iTermVersionComparatorTests` passes all 3 dotted-number, Python-version, prerelease, build-number, and large-component tests on 2026-08-29.
- `tools/build.sh` passes on 2026-08-29 with all non-updater Sparkle imports removed.
- `tools/run_tests.expect ModernTests/iTermSoftwareUpdateServiceTests` passes both forwarding and restart-state tests on 2026-08-29.
- `tools/build.sh` passes on 2026-08-29 after isolating application updates behind the app-owned service.
- `tools/build.sh` passes on 2026-08-29 after removing the uninitialized relay-operations gitlink and its only local helper.
- `tools/run_tests.expect ModernTests/MarkdownRenderingTests` passes all 3 native Markdown structure, style, front-matter, code-font, and literal-backtick tests on 2026-08-29.
- `tools/build.sh` passes on 2026-08-29 with the SwiftyMarkdown framework, project references, build rules, and submodule removed.
- `tools/run_tests.expect ModernTests/PortholeFoldClearTests` passes all 5 Porthole fold, unfold, and buffer-clear lifecycle tests on 2026-08-29 after replacing Highlightr with app-owned rendering.
- `tools/build.sh` passes on 2026-08-29 with the Highlightr framework, CSS resources, project references, build recipe, and submodule removed.
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
- Five submodules remain. Redundant `fmdb`, `BTree`, `MultiCursor`, `CoreParse`, and `libgit2` checkouts plus the optional regex-visualization, syntax-highlighting, third-party Markdown, updating, and relay-operations dependencies are gone; further removals require separate audits of surviving SSH, rendering, Companion, and build-tool paths.

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

Safe-first targets are exhausted; the remaining dependency removals require individual feature and runtime audits.

High-risk later targets:

- `submodules/NMSSH`, `submodules/libssh2`, `submodules/openssl`
- `submodules/libsixel`

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
- Validate the retained Sparkle 2 appcast packaging end to end after the app
  naming and signing chain are stable.

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

### 2026-10-04 Responsive Dialogs And List Guidance

- Make the profile inspector resizable with stable margins and proportional columns. Show readable color summaries while retaining full stored components in a selectable, scrolling text detail. Keep deleted profiles and empty searches explicit, and close with Escape.
- Give the snippet editor a responsive, larger form with monospaced text. Localize and attach escaping help to its editor, preserve literal text and tags, and handle Command-Return independently of AppKit default-button updates. Finish field editing before saving.
- Reuse one AppKit empty-state view for actions, snippets, and profile inspection. Offer add, clear-search, and show-all actions. Point the actions editor at its actual content container so it shares the responsive section layout and keeps import/export buttons inside the default viewport.
- Stop snippet edit notifications from falling through into the deletion case; refresh empty guidance and selection-dependent actions after model and search changes.
- Verification: all 56 SettingsNavigation/ProfileSetting/SettingDefinition ASan tests pass. A final focused inspector test also passes with a 40-line value preserved and scrolled to the last line. Four localization checks, plist validation, and git diff checks pass. Development and Deployment builds pass; clearing only generated precompiled headers resolves the existing cross-configuration module-map cache failure. Native Chinese screenshots cover minimum/wide sizes and Aqua/Dark Aqua. No new dependencies or submodule changes.
- Keep this roadmap local. No push, tag, notarization, or publication. The older 26.10.1 candidate predates these changes and was not regenerated in this pass.

### 2026-10-04 Latterm 26.10.1 Release Preparation

- Bump version.txt to 26.10.1 and write user-facing notes in docs/notes-26.10.1.txt. Correct README launch-suite, build-output, Chinese-localization, and platform details. Source commit: cac6a0f2c523fb6a2791efb10ecc1fd466105bf2.
- The previously verified 56 Settings/ProfileSetting/SettingDefinition ASan tests and the final 40-line inspector-value test remain valid. An additional 247 terminal-grid, screen, tmux-layout/key, session-restoration, preference-accessor, and version-comparator ASan tests pass. Four localization and four release-cleanup checks pass.
- Complete a fresh signed Deployment build in Build/ReleasePreparation/26.10.1/cac6a0f2c/Build. Verify Developer ID team R7ZJJDMW42, bundle com.ecnelises.latterm, version/build 26.10.1, hardened runtime, and macOS 12.4 minimum. Check all 17 Mach-O files support arm64, their deployment loads are at most 12.4, and no runtime dependencies refer to the developer’s home directory. Verify packaged Chinese NIBs/localizations and the font/action-picker resource bundles.
- Candidate: Build/ReleasePreparation/26.10.1/cac6a0f2c/Latterm-26.10.1-candidate.zip (26028187 bytes). SHA-256: aedfd60eedb6210438d32f93785d6e0356d36118e4cdc276c2c2548e2ab14e30. ZIP integrity and extracted deep/strict signature checks pass. candidate-manifest.json records source and binary verification. The earlier candidate in the parent directory is stale.
- After explicit user authorization to upload this exact candidate to Apple, notarization b273c292-7f78-467c-aaf0-c1f70ccf2746 was Accepted. Staple and ticket validation, deep/strict signature checks, ZIP integrity, and Gatekeeper (Notarized Developer ID) pass before and after final extraction. Final artifact: Build/Releases/26.10.1/Latterm-26.10.1.zip (26030154 bytes), SHA-256 2a35412ce97aa68eb9a1cfbe81816212bbfd69c704076fb7a6951a3929549f6b; the matching .sha256 file and release-manifest.json are beside it. After explicit release authorization, atomically push clean and annotated tag v26.10.1, whose peeled commit matches cac6a0f2c523fb6a2791efb10ecc1fd466105bf2. Publish https://github.com/ecnelises/latterm/releases/tag/v26.10.1 at 2026-10-04T13:10:02Z and set it as the latest stable release. Both uploaded asset sizes and GitHub SHA-256 digests match the verified local files. Keep this roadmap local.

### 2026-11-03 Bounded Upstream Review And Scroll-View Cleanup

- Read cursor `206cb5df9f58d55e68a119f93d2173d48f47d9a6`, fetched with `--no-recurse-submodules`, and inventoried 1,010 commits through `095beb457dca2a5ed4a9f155dc2b4dc7d9ef34a2`. This pass classifies only the first 79 commits, through `471cb5eabbf049f9d2b574c94d0132c9ab12e907`; the remaining 931 are NOT reviewed through. Deferred entries below remain roadmap work after advancing that bounded cursor.
- Official downloads: stable 3.7.6 (2026-10-15, `7ce456b98db38d3f0bafd70ffec87752e69d5d58`); test 3.7.7beta2 (2026-10-27, `8ea34d10285ac9af43bd550a901500b983f5063a`). GitHub Releases API is empty; official downloads and git tags are the release evidence. Compared tag contents: 3.7.2 to 3.7.6 has 2,166 changed files; stable to beta2 has 1,083. These are divergent release/master content comparisons, not counts of new applicable fixes. No claim of full release parity.
- Extra targeted release ports outside the bounded cursor: `07b79a4be` removes the obsolete Mojave scroller-reparenting workaround and setting; adapt `98124626f` by deleting the fork's Chinese strings. `20e9d3ebd` (stable branch; master origin `feefa7526`) treats missing/non-string trigger regex as empty. Stable-to-beta2 leaves the selected scroll/complex-char/ToolWrapper source files unchanged; Trigger has later changes requiring separate review.
- Prioritize subsequent release fixes for tmux detach (`6588dbd1b`, `db34734ba`, `23246de5f`), cleared-screen restoration (`bc0e53816`), and spacing-combining characters (`f63e43701`). Do not advance past unreviewed commits merely because these fixes were identified.
- Native dependency audit: none of these changes owns NMSSH/libssh2/OpenSSL, libsixel, or Companion CNoise. No submodule is added, removed, or staged.
- Verification: `tools/build.sh Development` passes with Xcode 27.2 after rebuilding native dependencies. All 9 ASan tests in SessionViewTests, ToolWrapperLifetimeTests, ComplexCharExpansionTests, and TriggerUntrustedDictTests pass. Four settings localization checks, strings plist validation, and diff whitespace checks pass. Existing ASan image-decoding notices, header nullability/documentation warnings, and AppIntents notices remain; changed sources introduce no warnings. Advanced-setting default was already NO; the removed legacy YES opt-in is intentionally retired and covered by a compatibility test.
- Advanced cursor to `471cb5eabbf049f9d2b574c94d0132c9ab12e907` only after those checks. New tests are auto-discovered by ModernTests synchronized group (the add-file helper was attempted but its Ruby xcodeproj gem is unavailable).
- Xcode 27.2 required local native dependency regeneration: ThirdParty frameworks/libsixel, password-manager adapters, and last-xcode-version now differ locally. These build inputs are kept separate from the exported source patch and are not staged. The submodule cleanliness preflight reported only pre-existing generated libraries/build directories; the sandboxed deps target then completed successfully. No commit, push, installation, or publication. Keep this roadmap local.

| Commit / subject | Disposition |
| --- | --- |
| `9f079b09c` ✨ feat(compact-tabs): show window name beside tabs | Defer: window-name label feature and sizing chain; separate terminal-window UI validation. |
| `7e3ac88fb` 🐛 fix(compact-tabs): unify window-name inset with tab fit | Defer: window-name label feature and sizing chain; separate terminal-window UI validation. |
| `d61f9f9b8` Add a snooze button to the Session Status toolbelt tool | Defer: independent app/UI/CLI improvement; retain as named candidate below for a focused follow-up with fork-specific layout/behavior checks. |
| `98682fc3d` Add generated bidi bracket-mirroring table | Defer: coupled RTL rendering/selection/copy chain; port together with later fixes and full bidi tests. |
| `076890622` Keep cursive scripts off the no-shaping fast path | Defer: coupled RTL rendering/selection/copy chain; port together with later fixes and full bidi tests. |
| `aa43e6cc0` Move the RTL annotation with row content in scrollRect | Defer: coupled RTL rendering/selection/copy chain; port together with later fixes and full bidi tests. |
| `f0478886e` Keep the reorder map on wrapped RTL lines in scrollback | Defer: coupled RTL rendering/selection/copy chain; port together with later fixes and full bidi tests. |
| `3cb9477f1` Align embedded LTR islands glyph-by-glyph in RTL lines | Defer: coupled RTL rendering/selection/copy chain; port together with later fixes and full bidi tests. |
| `ffa168ad2` Mirror brackets and reorder RTL text via CoreText resolution | Defer: coupled RTL rendering/selection/copy chain; port together with later fixes and full bidi tests. |
| `829b09cdd` Keep Arabic joining across a selection or SGR color split | Defer: coupled RTL rendering/selection/copy chain; port together with later fixes and full bidi tests. |
| `96a822b79` Bidi mouse selection: work in logical coordinates, drag visually | Defer: coupled RTL rendering/selection/copy chain; port together with later fixes and full bidi tests. |
| `1f4b1bd9a` Paste: option to strip zero-width bidi/format characters | Defer: bidi settings and migration need explicit default/compatibility review with RTL chain. |
| `32898d193` Consolidate alternate-screen bidi into one opt-out setting | Defer: bidi settings and migration need explicit default/compatibility review with RTL chain. |
| `986ccec7a` Bidi: release notes for RTL rendering, selection, and paste | Defer: coupled RTL rendering/selection/copy chain; port together with later fixes and full bidi tests. |
| `a53022501` Bidi rendering: consolidate coordinate converters and fix CoreText/DWC glyph alignment | Defer: coupled RTL rendering/selection/copy chain; port together with later fixes and full bidi tests. |
| `8fc18b6c1` Bidi selection: commit and expose selection in logical coordinates | Defer: coupled RTL rendering/selection/copy chain; port together with later fixes and full bidi tests. |
| `befcc4a91` Bidi copy mode: select in logical order regardless of visual direction | Defer: coupled RTL rendering/selection/copy chain; port together with later fixes and full bidi tests. |
| `73e5fda32` Bidi: route selection consumers through logical coordinates | Defer: coupled RTL rendering/selection/copy chain; port together with later fixes and full bidi tests. |
| `8969b1ada` Bidi Companion: report selection in logical coordinates | Defer: coupled RTL rendering/selection/copy chain; port together with later fixes and full bidi tests. |
| `f3c9345ae` Paste: strip additional zero-width bidi and format characters | Defer: bidi settings and migration need explicit default/compatibility review with RTL chain. |
| `095009a67` Alt-screen bidi migration: run after custom-folder prefs are copied down | Defer: bidi settings and migration need explicit default/compatibility review with RTL chain. |
| `27dc3c043` Add "Prevent sleep" profile setting and "Set Profile Setting" trigger | Defer: optional sleep-prevention/profile-trigger feature plus nil guard; absent in fork. |
| `5ff63dade` Overlay suite name on dock icon when launched with -suite | Defer: independent app/UI/CLI improvement; retain as named candidate below for a focused follow-up with fork-specific layout/behavior checks. |
| `ed0742596` Companion: link the setup wizard to the App Store at launch | Defer: coordinated Companion protocol/distribution/CLI slice, not main terminal maintenance. |
| `f7461f46c` 🐛 fix(compact-tabs): stop toolbelt drag from squeezing tabs | Defer: window-name label feature and sizing chain; separate terminal-window UI validation. |
| `74a166826` Add on-device AI-generated tab titles | Skip: removed AI/browser surfaces, including their compatibility fixes. |
| `97ce82002` Add an HDR cursor to the legacy and Metal renderers | Defer: HDR cursor/outline feature chain; preserve current rendering and defaults. |
| `94ec39222` Fix empty Keys > General tab in Edit Session after editing a browser session | Skip: removed AI/browser surfaces, including their compatibility fixes. |
| `04dd1cdaa` Add "it2 notify" to push a notification to the companion device | Defer: coordinated Companion protocol/distribution/CLI slice, not main terminal maintenance. |
| `5f6cf690b` Wire up the HDR cursor checkbox in Profiles > Colors | Defer: HDR cursor/outline feature chain; preserve current rendering and defaults. |
| `558e73494` Merge PR #731: show the window name beside the tabs in Compact and Minimal | Defer: window-name label feature and sizing chain; separate terminal-window UI validation. |
| `891d53570` Fix locale description color not adapting to dark/light mode | Defer: independent app/UI/CLI improvement; retain as named candidate below for a focused follow-up with fork-specific layout/behavior checks. |
| `1b39812c2` Log when the window-name-beside-tabs label is squeezed | Defer: window-name label feature and sizing chain; separate terminal-window UI validation. |
| `96ccad4a4` Localize iTerm2 (String Catalogs, pt-BR/zh-Hans, plurals, i18n infra) | Skip wholesale localization/XIB import: fork has independent Settings layout and Chinese resources; evaluate individual UX issues separately. |
| `82c0d26fe` Fix crash with HDR cursor in Metal | Defer: HDR cursor/outline feature chain; preserve current rendering and defaults. |
| `8cae92b81` Add German, Japanese, and Russian localizations | Skip wholesale localization/XIB import: fork has independent Settings layout and Chinese resources; evaluate individual UX issues separately. |
| `0cb1d8e02` Complete Japanese and Russian localizations | Skip wholesale localization/XIB import: fork has independent Settings layout and Chinese resources; evaluate individual UX issues separately. |
| `ae674265c` Adjust UI to fit localized strings and fix related issues | Skip wholesale localization/XIB import: fork has independent Settings layout and Chinese resources; evaluate individual UX issues separately. |
| `69357dfc5` Polish German, Japanese, and Russian translations | Skip wholesale localization/XIB import: fork has independent Settings layout and Chinese resources; evaluate individual UX issues separately. |
| `ccf263742` Shorten Russian strings and document brevity for animal names | Skip wholesale localization/XIB import: fork has independent Settings layout and Chinese resources; evaluate individual UX issues separately. |
| `bd1549b55` Widen Settings fields in PreferencePanel to fit translations | Skip wholesale localization/XIB import: fork has independent Settings layout and Chinese resources; evaluate individual UX issues separately. |
| `a15a6caca` Shorten and refine de/ru/pt-BR translations | Skip wholesale localization/XIB import: fork has independent Settings layout and Chinese resources; evaluate individual UX issues separately. |
| `8dbf35b0f` Various localization fixes | Skip wholesale localization/XIB import: fork has independent Settings layout and Chinese resources; evaluate individual UX issues separately. |
| `08fc1e090` Remove the revision-11 relay migration machinery | Defer: coordinated Companion protocol/distribution/CLI slice, not main terminal maintenance. |
| `905ab8695` Fix white rectangle right of a collapsed tab group in Minimal theme | Defer: independent app/UI/CLI improvement; retain as named candidate below for a focused follow-up with fork-specific layout/behavior checks. |
| `57a81913d` Put tab bar in titlebar for accessory/maximized/centered windows on macOS 26 | Defer: independent app/UI/CLI improvement; retain as named candidate below for a focused follow-up with fork-specific layout/behavior checks. |
| `79b056097` Fix Companion reconnect wedge: honor task cancellation in RelayTransport.receive() | Defer with priority: RelayTransport cancellation fix and tests; validate Mac/iPhone shared package together. |
| `0f7e0d6d6` Fix two beta11 crashes in session launch | Already adapted: directory-launch lifetime and Actions redraw are in local history; removed browser portion skipped. |
| `a0f08f179` Fix Actions settings not redrawing action column on edit | Already adapted: directory-launch lifetime and Actions redraw are in local history; removed browser portion skipped. |
| `eadbf069c` Make utility preference sheets titled so they can become key | Defer: independent app/UI/CLI improvement; retain as named candidate below for a focused follow-up with fork-specific layout/behavior checks. |
| `2e809cc67` Add a note about how to run the app | Skip documentation-only policy/comment changes; retain local agent/build rules. |
| `46bbd5803` Warn that iTermShortcutInputView needs a key-capable window | Skip documentation-only policy/comment changes; retain local agent/build rules. |
| `aff41a226` Check the current session's workgroup in Shell > Workgroups | Defer: independent app/UI/CLI improvement; retain as named candidate below for a focused follow-up with fork-specific layout/behavior checks. |
| `b120f0f22` Set workgroup checkmark in validateMenuItem, the reliably-called seam | Defer: independent app/UI/CLI improvement; retain as named candidate below for a focused follow-up with fork-specific layout/behavior checks. |
| `e25ccdd45` Fix crash on global search with a browser session | Skip: removed AI/browser surfaces, including their compatibility fixes. |
| `aefc0e051` Reduce logging verbosity in rootTerminalViewShouldLeaveEmptyAreaAtTop | Defer: independent app/UI/CLI improvement; retain as named candidate below for a focused follow-up with fork-specific layout/behavior checks. |
| `c3a697eb9` Fix Claude Code onboarding: workgroup layout is under Arrangements, not Shortcuts | Skip: removed AI/browser surfaces, including their compatibility fixes. |
| `cfd5af485` it2: list subcommands alphabetically in help | Defer: independent app/UI/CLI improvement; retain as named candidate below for a focused follow-up with fork-specific layout/behavior checks. |
| `88228e721` Guard nil shared controller in sleep-prevention recompute | Defer: optional sleep-prevention/profile-trigger feature plus nil guard; absent in fork. |
| `d65c5f096` Rebuild Sparkle and update to commit that respects -suite | Skip: updater removed from the current fork; do not restore Sparkle submodule/binaries. |
| `43bd1e07e` Coalesce mouse-mode-change side effects to fix tmux hangs | Defer with priority: mouse-mode notification coalescing; parser/delegate tests must accompany port. |
| `2f4efd802` Add register_timer: AI chats can act after a delay or at a set time | Skip: removed AI/browser surfaces, including their compatibility fixes. |
| `fe763cef2` Harden complex-char expansion and add a CoW mutation check | Port expansion bounds and surrogate safety with regression tests; defer beta-only LineBlock CoW instrumentation to dedicated snapshot/mutation suite. |
| `bb6536edc` Get rid of stupid menu icons | Defer: independent app/UI/CLI improvement; retain as named candidate below for a focused follow-up with fork-specific layout/behavior checks. |
| `1f1f41057` Switch to appstore companion | Defer: coordinated Companion protocol/distribution/CLI slice, not main terminal maintenance. |
| `8e6f0383e` Change compaion app store URL to link to my page with a QR code you scan with your phone | Defer: coordinated Companion protocol/distribution/CLI slice, not main terminal maintenance. |
| `54a50da3c` Bump deployment target in pre-build summary | Skip: preserve fork macOS 12.4 baseline, no implicit deployment-target increase. |
| `ffe479e32` Gate the Tahoe selected-tab HDR outline behind a new setting | Defer: HDR cursor/outline feature chain; preserve current rendering and defaults. |
| `c7e81b9d1` Fix z order and alignment of command warning | Defer: independent app/UI/CLI improvement; retain as named candidate below for a focused follow-up with fork-specific layout/behavior checks. |
| `67806999a` Fix python docs build scripts for new path to MainMenu.xib | Already adapted: terminal-only menu API/docs regenerated against relocated main menu. |
| `bf04c0465` Add missing menu item identifiers | Defer: independent app/UI/CLI improvement; retain as named candidate below for a focused follow-up with fork-specific layout/behavior checks. |
| `ce706b849` Rebuild main menu rst file | Already adapted: terminal-only menu API/docs regenerated against relocated main menu. |
| `cedc21be0` Complete Simplified Chinese (zh-Hans) localizations (100% coverage) (#744) | Skip wholesale localization/XIB import: fork has independent Settings layout and Chinese resources; evaluate individual UX issues separately. |
| `78e001bb4` Remove a bad word | Skip documentation-only policy/comment changes; retain local agent/build rules. |
| `4fe0968fb` Make concatenated localized strings use format placeholders | Skip wholesale localization/XIB import: fork has independent Settings layout and Chinese resources; evaluate individual UX issues separately. |
| `e63b7e09f` Translate remaining zh-Hans strings that were left in English | Skip wholesale localization/XIB import: fork has independent Settings layout and Chinese resources; evaluate individual UX issues separately. |
| `3609834cb` Settings: replace wrap-around field labels with single labels | Skip wholesale localization/XIB import: fork has independent Settings layout and Chinese resources; evaluate individual UX issues separately. |
| `46d74e543` Make smart-selection rule names fully translatable | Skip wholesale localization/XIB import: fork has independent Settings layout and Chinese resources; evaluate individual UX issues separately. |
| `471cb5eab` Fix leak of individually-removed toolbelt tools and scope ProfileListView undo | Port ProfileListView undo cleanup; also adapt prerequisite ToolWrapper binding-cycle removal from localization-era code without importing localization stack. |

### 2026-11-03 Tmux Notification And Mouse-Mode Follow-Up

- Committed the preceding source-only maintenance slice as `827b71b5e`; roadmap, regenerated native dependencies, and submodules remain outside that commit.
- Tracking policy: UPSTREAM is a reviewed-through master cursor, not a release baseline. Prioritize stable 3.7.6 fixes; compare beta contents and selectively adapt master fixes only with relevant regression coverage. No blanket beta merge or claim of release parity.
- Ported stable `23246de5f` (master origin `02abd97be1f45290a8b757e367587e5469eb2a51`): only sessions that asked to close after tmux detach consume the broadcast answer. Restart clears the pending state. Five tests cover Always, Never, restarted sessions, dismissed offers, and repeated offers.
- Resolved deferred `43bd1e07e`: mouse-mode setters alone notify on real changes, removing redundant reset/DECSET/menu notifications. Also ported master-only `f49137e8a` (after 3.7.7beta2): join before the side effect reads the main-thread snapshot, so CSI ? 1003 h enables motion tracking immediately. Five parser tests include repeated assertions and draining effects before syncing. No new task-I/O infrastructure is imported.
- All 10 selected ASan tests and `tools/build.sh Development` pass; whitespace checks pass. Existing test-source warnings and AppIntents notices remain; changed files introduce no warnings. ModernTests discovers both new files through its synchronized group; add-file helper remains unavailable because xcodeproj Ruby gem is absent.
- No submodule or dependency changes are introduced by this slice. UPSTREAM remains `471cb5eabbf049f9d2b574c94d0132c9ab12e907`; this closes a deferred candidate and cherry-picks later fixes, not a review of the remaining continuous range. Next high-priority work: detached tmux controller actions and cleared-screen session restoration, then remaining master classification.

### 2026-11-03 Stable RTL And Unicode Port

- Ported the existing RTL shaping/selection corrections: `98682fc3d`, `076890622`, `aa43e6cc0`, `f0478886e`, `3cb9477f1`, `ffa168ad2`, `829b09cdd`, `96a822b79`, `a53022501`, `8fc18b6c1`, `befcc4a91`, `73e5fda32`, and `7b98b5378`. Preserved the fork's removed-product boundaries and stale-find range check.
- Ported Unicode width and predecessor merging: `1b6b3ccb6`, `4c8d54a8d`, `f63e43701`, `ec087cf9b`, `1f95cec9c`. Updated generator/template with stable bidi-mirroring handling (`4ef38be0a`) so regeneration preserves the fixes. FullWidthFlags still defaults to YES; its label now accurately describes lone indicators.
- Ported `a804fab2c` content-generation-based grid persistence and migration-compatible keys. All metadata mutations still invalidate saved state.
- Verification: 492 ASan tests passed across RTL display/selection, Unicode conversion, predecessor merging, grid persistence, line buffer and restoration; 4 localization checks passed. No submodule changes. Development build passed.
- This is another verified subset, not full 3.7.6 parity. User explicitly requires all applicable stable fixes before release; version bump, push, notarization, and upload remain pending. UPSTREAM remains unchanged.

### 2026-11-03 Stable Scheduling And Keyboard State

- Ported `6e176764d`, `daa957956`, `4915720d4`, `670502bb2`, and `e54e01d4c`: coalesced report syncs, bounded batched-OSC livelock coverage, urgent surviving conductor callbacks, and deadline/generation-based deferred scheduling. Did not restore the removed conductor-start injection path.
- Ported `13376a630`, `2f1d7bf65`, `ccdd42310`, `1acab0d1d`, and `8242815bc`: Kitty SET changes the current stack frame; command-boundary snapshots distinguish shell-managed modes; tmux owns pane key encoding and mode display across detach.
- 143 ASan tests passed across query coalescing, urgent/deferred scheduling, shell reset offers, tmux names/modes, mouse state and screen restoration. Development build passed. No submodule changes.

### 2026-11-03 Stable Rendering, Images And Search

- Ported `261d575d2`, `50363ae0b` with `cee9cc21d` final crop behavior, `2e78c185a`, `dba132dd2`, and `acbd9d7bd`: Kitty placeholder ID defaults and placement identity, stale-image replacement, line attribute clearing, aliased-glyph clearing, and immutable font descriptor identity. Kept the browser-free FontTable initializer in the GPU regression.
- Ported `eb8ea03e4`, `710d0f737`, `754761537`, `2e7e76919`, `21b438039`, and `fe54bd10c`: null padding, backward-search wrap boundaries, all-null selection resizing, and interior nulls searched as spaces. Adapted selected upstream regressions into StableScreenSearchResizeTests instead of importing the unrelated legacy-test migration.
- Ported `8f3ecc772` token queue initialization race, `800dcf986` filename sanitation, and the generic DVR length overflow guards from `2765edb79`; skipped the latter's removed browser layout branch.
- ASan: 445 tests initially, 1 environment skip (current macOS font hashes already agree) and a test-only initializer mismatch; corrected that mismatch, with 345 other affected cases passing and the final GPU/line-attribute retest passing 137 tests. Cleared introduced Swift nullability/cast and ObjC bitmap enum warnings. Existing runtime thread-performance diagnostics are not compiler warnings. Development build passed. No submodules changed.

### 2026-11-03 Stable Tmux Capture And Window State

- Ported `cecaae04d`: version-gated tmux 1.8 exit workaround, response-block parser state, and deferral of early window captures.
- Ported `d2de7d6a4`: capture latest terminal user variable/location/version metadata while a pane opens, applying it after restored cursor state; no scripts or installation hooks added.
- Ported `d5b299707` and `94a40e856`: honor background new-window and count only window changes that produce a notification. Adapted for the fork's absent border-status cache while preserving detached-gateway guards.
- 116 ASan tests passed, including two added current-window notification regressions. Development build passed. No submodule changes.

### 2026-11-03 Stable OSC 7, Paste And SSH

- Ported `851561542`, receiver portion of `92b5b854e`, `673520779`, and `70c88ebeb`: exact local names and boot identity, locality precedence, and remote directory preservation. Omitted removed shell installation scripts and warning UI. Moved the machine identity helper into FileTransfer. Did not reintroduce subsequently reverted ssh-exit heuristics.
- Ported `32450755c`, `64791fc3c`, `35e05ff3f`, `120de33b4`, and `da38f0acc`: bounded previews, stable paste choices, batch uploads, actual destination paths, cancellation cleanup, chunking and unique remote names. Preserved fork localization approach and MRC ownership.
- Ported `a66f730ef`, `9ee9751cc`, and `5e9018b0a`: conductor pipeline state/latency and abrupt disconnect parser recovery.
- 179 locality/paste tests and 38 upload/disconnect tests passed under ASan; Development build passed with no introduced compiler warnings. No submodule changes. UPSTREAM remains unchanged until remaining stable range review is complete.

### 2026-11-03 Stable Input And App Lifetime

- Ported `efbb9553a`, `0e17f7774`, `e71838655`, `52fdf260e`, and `df780a158` (with only the keystroke matcher extraction from `3541ec9c3`): Kitty/termkey, IME and legacy key format compatibility. The new physical-shortcut suggestion product UI was not imported.
- Ported `9f17e76ef`, `419487eb4`, `dece2b56d`, `dd65a6b9d`, `52c8dab89`, `dbf0fa199`, `1f58a4f5c`, `03c6d1c3b`, `72707c178`, `09894ed6e`, `4478e9ab5`, and `4a5efa158`: accessibility corrections, focus/window lifetime and popovers.
- Ported `014df33c7`, `d2244451b`, `e1f5e2f3d`: spawn PATH/signals, current-process server ownership and literal environment parsing. UsePosixSpawn defaults to NO, preserving stable/fork behavior.
- Ported `51952da84`, `49ebe2949`, `4c75d8536`, `edb295b98`, `ed7be8179`, `fbaa610a0`, `20b455b5a`, and `db1ce26aa`: settings serialization/relaunch, logging, histogram, notification and API style safety.
- Ported `8b865198a`, `709472649`, `762644229`: editor launch/URL compatibility. Adapted tests to the fork's browser-free openPath API.
- Ported `b1c44b549`, `77536e9c7`, `5a7aa1726`, `df0010277`, `87560f65e`, `a82b7776e`, `93f4367f6`, `5c60f1323`: git/completion rendering, redundant views and outline/script-history leaks. Kept browser loggers removed and replaced AI-setting references in tests with surviving secure settings.
- ASan suite ran 249 tests: 245 passed initially; four style assertions exposed missing prerequisite `20b455b5a`. After adding its URL assignment all 6 API style tests passed. Test-only missing imports/helpers and removed target arguments were corrected. Development build and 4 localization checks passed. No submodule edits.

### 2026-11-03 Stable Persistence And Status Evaluation

- Ported `14d64bd21` and `f728dd7c8` SQLite NORMAL/WAL/checkpoint handling, `75e03729b` dynamic profile type validation, and adapted `54cba431c` tab color absence tracking without the fork's absent OSC palette-binding feature.
- Ported `0c8687976` and `3d8766648` status reload coalescing, evaluator reuse and late-read async dependencies; used the `a6c0e15e7` regression revision to exclude environment-dependent tests. Ported `78dffc2f7` typed bookmark-mark calls.
- Adapted only the stale alternate-grid bidi clearing from `32898d193`; keep AlternateScreenBidi name/default/values rather than rename/invert the setting. Therefore `095009a67` migration is unnecessary.
- 63 ASan tests passed for configuration, color reset, graph persistence, status/evaluator lifecycle and RTL. Development build passed. No submodule changes.
- Classified `97a43cd12` as inapplicable: KittyDnDController/Message were removed. `119e41381` is inapplicable: the Set Profile Boolean trigger/terminal delegate surface is absent. `20e9d3ebd` is already covered by the first maintenance commit's missing-regex handling. `d84fbcbd7` is inapplicable: UKCrashReporter XIB is removed. `a30762d17` stack-block array is absent from fork tab menu. `04d02ca49` fixes the newer forward-URL-extension implementation, which is absent here; assess `52f95bb02` independently against existing URL selection.

### 2026-11-03 Stable API And Tab Titles

- Ported `ed1dfdea6` focus deferral for affected Python client versions and explicit selected-tab/active-session protocol fields; regenerated with protoc 3.21.11 and current mypy-protobuf in an isolated temporary environment. Retained fork protocol fields.
- Ported `6b64d5802`, `f4b87c0d0`, `9c723df48`, and `19525cd35`: unified tab labels, synchronous formatting updates and reentrancy guards. Kept browser-specific blank-name suppression removed and retained the fork nil fallback.
- 40 ASan tests passed; Python selection fields passed a serialization round trip. No submodule changes.

### 2026-11-03 Stable Shutdown, Input And Resource Safety

- Ported `253e423a9`, `2437bfba6`, `1ba7be767`, `582002ffb`: CLI cookie requests no longer launch a quitting app, shutdown closes the API listener, and macOS text substitutions no longer alter terminal keystrokes. Documented the terminal text-substitution behavior change in release notes.
- Adapted `72c85bfd1` archive-directory fallback while retaining the existing archive API (not the optional archive-based Undo Close feature). Ported `d5bcfdf18` visible locale-prompt routing and `57978e823` required-resource failure handling without browser resources.
- Adapted `f474bbe54` provider-owned lock observation to the existing RequireAuthenticationAfterScreenLocks policy; did not import the new authentication-mode product option.
- 26 ASan tests passed including onscreen transparent/opaque windows, input replacement, password-lock behavior and graphic resource maps. No submodules changed.

### 2026-11-03 Stable URL Selection And Live Status

- Ported `52f95bb02` URL parsing and selection action with browser-free external opening; retained conservative guessing and missing-file behavior. No split-browser actions restored.
- Ported `1c71cd978` live workgroup toolbar flags and the pre-existing-status baseline initialization from `b48184b46`. The latter's done/error acknowledgment path depends on the absent TabStatusController/new canonical status feature and is inapplicable here.
- 78 ASan tests passed across URL selection and workgroup state. No submodule changes.

### 2026-11-03 Stable Password Adapter And Shell Recovery

- Ported `73e1d7d53`, `ba0042135` with the `152b74ee4` shell-service prerequisite, and `5c7a35dd4`: nullable PATH failures with bounded retries, shell-mode compatibility, cached adapter PATH, real Bitwarden errors, concurrent pipe draining, generation-aware session recovery and bounded recipe retries.
- Adapted the optional authentication-error/list-warning protocol fields needed by the existing adapter protocol; preserved the fork's pre-unified-edit request structures, browser-free constructors, raw localized strings and redacted logs. Kept `35ca9f4f8`/`236baa8f8` AI Usage-only environment additions removed; used the applicable ba0042135 test revision.
- 35 ASan tests passed, then 13 final retry/error-classification tests passed. All installed shell argument shapes passed. Four real-process tests against a fake bw verify bad passwords, stale sessions, rejected fresh sessions and network errors without touching a real vault.
- The real-process tests exposed stale SwiftPM paths in pwmplugin/build.sh: current SwiftPM writes out/Products/Release while the script copied an old arm64-apple-macosx/release binary. Updated both adapter and it2 scripts to query --show-bin-path, then rebuilt signed helpers. No submodule changes.

### 2026-11-03 Stable Tmux Geometry And Cursor Input

- Ported `918fc2762`, `6bf0b1426`, `2f4e6740f`, `f8bb3771f`, `4f979134d`: per-pane requested focus reporting, tmux border-status row geometry, relist cache, titlebar resize notices, single-window dashboard action and per-session toolbar dimensions. Preserved the newer current-window notification fix and merged geometry tests into existing malformed-layout coverage.
- Adapted `28dec2146` to the fork's refactored layout path; `29fa4d33e` new-tab wording (close-tab wording already correct; tab groups absent); `c8463d6ab` inset-aware credits sizing only (new About treatment absent). Ported `c54b27dad` recent-input cursor animation gate with a translated Expert Setting and documented behavior change.
- 24 tmux geometry tests and 35 retained control-mode/notification tests passed under ASan. Four Settings localization checks passed.
- `429b475f0` depends on the absent scrollable-tab/collapse accessory implementation (hideAccessoriesOutsideScrollRegion and scrollOffset do not exist here), so no new tab-scrolling product surface imported. `885631fdf` fixes the absent windowNameBesideTabs feature. `92c4ea620` fixes seams in the newer height-scaled dark-pill renderer; the fork retains fixed-size caps and does not contain that implementation.

### 2026-11-03 Stable Editor Lifetime And Window Controls

- Ported b563be9a5 hotbox slide controls and cancelable animations, f13c0e1c5 editor undo lifetime safety and focused-editor undo routing, 603a9a16e nullable Python arguments, ef595b4e6 Composer resize reconciliation, and c248641ea password working-label alignment. Preserved the existing Undo Close fallback; df3f56589 migration notice is inapplicable because that behavior was not removed.
- 19 ASan tests passed initially; the undo regression needed an explicitly completed undo transaction before checking cleanup. All 3 final undo/animation tests passed. Four localization checks passed. No submodule changes.

### 2026-11-03 Stable Pane Focus

- Adapted bc36feb8f to retained terminal, Find, Composer, Clippings and Session Note views. Removed the old per-text-view tracker; preserved stolen-focus cursor rendering through the new coordinator. Added the optional within-pane setting using existing manual Settings geometry, with Chinese localization. Browser and AI views remain absent.
- 39 pure focus-state tests and 13 real-window integration tests passed under ASan. Integration fixture omits floating-pane and AI helpers absent from the fork.

### 2026-11-03 Stable Filtered Tmux And Launch Recovery

- Adapted ab5c56888 and its prerequisite view-map correction to resolve filtered stand-ins through live pane IDs. Covered both active-pane selection and view reuse/new-session registration, without floating-pane support. All 7 ASan identity and real-layout tests passed.
- Ported 439c7c925 translocation recovery through the fork defaults wrapper, using null output handles to avoid blocking xattr pipes. Ported 0cfbd7eaa and 660c95167 menu-shortcut collision fixes with explicit release notes. Ported 08e98eaf0 nil-title Companion tree handling.
- fb66994c0 toolchain changes are already covered by the fork's explicit captures, caught async writes (including user-visible errors), and unsupported-format default. 623ecbfab targets removed railroad_dsl. aebf95a06 targets absent InfoPlist.xcstrings; local InfoPlist overlays contain no version keys. 0a283a1a4 concerns Companion networking, not terminal wheel reporting; review with the retained Companion bridge.

### 2026-11-03 Stable Companion Terminal Transport

- Ported the terminal-only portions of 101fe2302, b387e2980, b871b222c, e26c73321, 0a283a1a4 and db38c6dca: off-main link/park supervisor, generation and closed-link guards, room-secret write exclusion during unpair, stream acknowledgements and rejection of input during main-queue stalls. Kept the fork protocol and omitted AI availability, push/chat classification and optional remote-modal answering. Imported the final stable versions of the new transport classes, then adapted them.
- Preserved macOS 12.4 with LockedState backed by the existing Mutex, rather than raising deployment for OSAllocatedUnfairLock. ModernTests links the app's existing iTermSwiftPackages framework so protocol error types share one runtime identity. 59 ASan tests passed, including real Noise handshakes and modal freezes.
- Also resolved previously deferred 79b056097 relay cancellation and 8969b1ada Companion bidi selection; both still apply to retained terminal control and need their focused checks below.

- Final checks: 9 additional bidi/stall-tracker ASan tests and the shared-package RelayReceiveCancellationTests passed. Development build passed with no introduced warnings. No new package or submodule was added.

### 2026-11-03 Stable Review Closure

- Release scope is official v3.7.6, commit 7ce456b98db38d3f0bafd70ffec87752e69d5d58, not beta. Reviewed all 414 commits from the prior cursor, including release-branch commits not on master. Compared v3.7.7beta2 (8ea34d10285ac9af43bd550a901500b983f5063a) and master (095beb457dca2a5ed4a9f155dc2b4dc7d9ef34a2); master-only features/fixes remain a separate follow-up below. No claim of beta/master parity.
- Resolved earlier UI deferrals 891d53570, eadbf069c, aff41a226, b120f0f22, 57a81913d, c7e81b9d1 and bf04c0465. Settings/Workgroup ASan suite: 121 passed; 4 localization checks and Development build passed. Fork key-mapping editor is no longer an NSPanel, so no absent panel restored. Regenerated retained menu identifiers also drops the obsolete updater entry.
- Earlier 79-commit table is historical: the later verified port batches supersede its RTL, mouse, relay, selection and UI deferrals. Remaining entries describe optional new features/cleanup or removed surfaces, not unported applicable 3.7.6 bugs. Keep HDR cursor, tab groups/window-name label, Prevent Sleep, new paste stripping policy, new archive Undo Close, new authentication policy, floating panes, OSC 7501, remote modal controls, and new shell installers out of this maintenance release. Preserve current defaults.
- Companion 6443852b0 is included: primary-authoritative mirror fallback, monotonic version floor, bounded resolution and detailed failure reasons. The Mac uses delayed fallback and the existing consent plugin; custom resolvers never use the official mirror. 122 shared-package and 4 Mac ASan tests passed. iPhone camera/controller-only changes remain a separate iOS release, not Mac runtime omissions.
- All five retained submodules are still live (NMSSH, libsixel, OpenSSL, libssh2, CNoise). No gitlink changed. Rebuilt arm64 CoreParse/NMSSH/libsixel from existing sources with Xcode 27.2; minimum OS 12.0 in dependencies, compatible with app baseline 12.4, and only system/bundle-relative dylib links.
- Final verification and release status will be appended after build/signing. This roadmap remains local.

#### Stable 3.7.6 Per-Commit Dispositions

| Commit / subject | Disposition |
| --- | --- |
| `df3f56589` Make the Undo Close migration notice app-modal | Defer feature: archive-based Undo Close replacement; retain existing Undo Close and no migration prompt. |
| `f13c0e1c5` Route Cmd-Z to the focused editor and add an undo-safety net | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `523d527a0` Localize the undo feature's user-facing strings | Skip wholesale catalog import: preserve fork Settings layout and Chinese localization; touched retained strings checked separately. |
| `335682100` Rebuild Localizable.xcstrings with extract_strings.sh as the canonical baseline | Skip wholesale catalog import: preserve fork Settings layout and Chinese localization; touched retained strings checked separately. |
| `74a08a792` Document extract_strings.sh as the canonical catalog serializer | Skip wholesale catalog import: preserve fork Settings layout and Chinese localization; touched retained strings checked separately. |
| `c1b8f49d8` Re-add make run-nobuild to relaunch without rebuilding | Skip upstream-only documentation/test infrastructure/release bookkeeping; use fork build, focused tests and release workflow. |
| `ee0613322` Fix crash restoring 3.6.11 scrollback that contains bidi text | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `b1c44b549` Tint git toolbar arrows and fix shared-static leak | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `77536e9c7` Show embedded newlines in completion rows as a return glyph | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `6cd2c00e5` Password manager: add "Require Authentication on Every Open" | Defer feature: new every-open authentication policy and dependent fixes; preserve existing authentication defaults. Existing screen-lock bug ported separately. |
| `4067a7619` Decode Ollama tool arguments as AnyCodable, not String (#748) | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `71da46860` Add live Ollama tool-call tests for non-string arguments | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `d5dd9e7e2` Companion: fix black QR scanner preview on first camera grant | Defer separate iOS delivery: camera preview and iPhone reconnect controller; no macOS runtime change. Shared relay cancellation ported. |
| `3639cec3c` Bump companion to version 1.1 (1) | Skip: iOS version/project regeneration or comments; no change to the released Mac binary. |
| `b7df732ef` Add regression test for URL detection across blank lines (13011, 13020) | Skip: newer forward URL extension implementation absent; schemeless URL fix ported separately. |
| `2f1d7bf65` Sample key reporting flags at FTCS D, not after the next prompt | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `4ea4c6ddd` Duplicate Tab: keep a duplicated tab in its group | Skip: tab-group implementation and associated drag tests are absent in the fork. |
| `97a43cd12` Fix kitty drag-out failing with EINVAL:unexpected t=e (12961) | Skip: KittyDnDController and drag-out protocol removed. |
| `ed1dfdea6` Fix Python API current_tab/current_session None after async_create | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `61ecdef61` Fix a bug where removing a tab from the middle of a tab group gives you a discontiguous group | Skip: tab-group implementation and associated drag tests are absent in the fork. |
| `6f105467f` Fix the tab group outline in Tahoe theme, which was clipped improperly | Skip: tab-group implementation and associated drag tests are absent in the fork. |
| `92c4ea620` Fix a faint vertical line inside selected tabs in the dark Tahoe theme | Skip: absent height-scaled Tahoe pill renderer; fork uses fixed cap geometry. |
| `61a57169f` Reorder items in the tab context menu. | Defer optional behavior change: tab menu reordering and adjacent duplication default; preserve fork defaults. |
| `28dec2146` Fix Tahoe tab bar shrinking/shifting after Lion fullscreen | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `e0f556720` Add tool to sanitize private info from the iTerm2 plist | Defer optional tooling: new private-plist sanitizer; no sanitizer installed in this fork. |
| `53af4ff4d` Sanitizer: redact Foreground Job Ancestors arrangement key | Defer optional tooling: new private-plist sanitizer; no sanitizer installed in this fork. |
| `5a41d596a` Require updating the plist sanitizer for new private defaults keys | Skip upstream-only agent policy for optional plist sanitizer. |
| `a7f2af565` Fix retain cycle in browser. Issue 13009 | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `268c28405` Harden TmuxLayoutParser against empty and malformed layout strings | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `522828a35` Reset notes-3.7.txt to only post-3.7.1 (unreleased) items | Skip upstream-only documentation/test infrastructure/release bookkeeping; use fork build, focused tests and release workflow. |
| `7cf9bcd2d` Point agents at the release-notes guidelines; document cumulative-file hygiene | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `02d86634e` Open duplicated tabs adjacent to the original by default | Defer optional behavior change: tab menu reordering and adjacent duplication default; preserve fork defaults. |
| `ccdd42310` Do not falsely offer to reset key reporting on a stray FTCS D | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `833006686` Fix companion wizard storing the API key on the wrong vendor (#754) | Skip: absent AI wizard, live model harness and AI-agent menu-bar status surfaces. |
| `ef595b4e6` Fix text not fitting in autocomposer and not enough space below separator | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `f914b1491` Sign Sparkle's nested Autoupdate helpers with Developer ID | Skip: Sparkle updater and sign_update no longer used; no removed updater dependency restored. |
| `27bffb924` Ban merge commits: always squash-merge PRs | Skip upstream-only documentation/test infrastructure/release bookkeeping; use fork build, focused tests and release workflow. |
| `6e176764d` Coalesce OSC 4 color-query report syncs. Issue 13013 | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `439c7c925` Fix auto-update failing when running translocated from Applications | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `b78faaa6f` Fail loudly on notarization and staple errors in release scripts | Equivalent: fork release script already fails on signing/notary/staple/Gatekeeper failures and checks the extracted final ZIP. |
| `4665948ac` Answer CSI 16 t (report character cell size) | Defer feature: new cell/window frame queries and BDSM/SCP control sequences; existing terminal protocols preserved. |
| `daa957956` Coalesce cursor-position and other DSR report syncs | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `0c1f56822` Add control sequences to set and report window frames and to report screen frames. | Defer feature: new cell/window frame queries and BDSM/SCP control sequences; existing terminal protocols preserved. |
| `f18603ba2` Companion: add protocol revision 13 for AI decoupling | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `560e568ee` Companion: advertise AI availability in the host hello | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `0a924239a` Companion: add the aiAvailabilityChanged host event | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `65c767136` Companion: drop AI from the pairing gate, keep it advisory | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `e2f0285c1` Companion: bridge serves non-AI requests when AI is off | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `5d452a0c6` Companion: fork the setup wizard on AI vs terminal-only | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `6297eb300` Companion: drop dead AI gate handling from the classic window | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `ddf192f33` Companion (iOS): track the paired Mac's AI availability | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `90a5427e1` Companion (iOS): disable chat surfaces with an explanation when AI is off | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `5d3c23ad2` Companion: release notes for AI-optional pairing | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `e0f9ea08c` Companion: stop AI-plugin probe log spam when AI is off | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `97e907c28` Companion: push live session-tree updates to the phone | Defer feature: pushed live session trees; current request/reply terminal tree retained, nil-title fix ported. |
| `c4802455a` AI: stop re-logging the same plugin-load failure on every probe | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `2d5cfbc25` Companion: live-update session names, rate-limited | Defer feature: pushed live session trees; current request/reply terminal tree retained, nil-title fix ported. |
| `a0379b597` Companion: serve terminal alerts over syncSince even when AI is off | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `d23e31f9e` Companion: don't offer AI setup in the wizard when AI is admin-disabled | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `9e36a7f18` Companion (iOS): keep aiAvailable accurate across reconnect and re-enable | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `1901642c2` Companion: regenerate Xcode project after rebasing on origin/master | Skip: iOS version/project regeneration or comments; no change to the released Mac binary. |
| `2b8703b91` Companion: centralize AI gating and fix per-message gating bugs | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `a3ac93da1` Companion: propagate AI plugin install/remove to a connected phone | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `edfd3dec3` Companion: refresh the pairing window's AI advisory when AI toggles | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `5b4788bca` Companion (iOS): harden reconnect handshake retry and dedup session-tree push | Defer separate iOS delivery: camera preview and iPhone reconnect controller; no macOS runtime change. Shared relay cancellation ported. |
| `c0c066626` Companion: don't move the message floor in syncSince when AI is off | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `6d9a0696e` Companion: route aiAvailable() through its tested pure core | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `62306c58f` Companion (iOS): unify handshake application and fix AI-toggle edge cases | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `4f487debf` Companion: don't self-perpetuate NSE wakeups when AI is off | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `7f2564c74` Companion: don't tear down an active pairing when AI toggles | Skip: AI availability/chat sync and revision migration. Fork has no AI pairing gate, chat/NSE push sync implementation to repair. |
| `b52b6b1fe` Companion (iOS): fix stale best-effort comment on reconnect handshake | Skip: iOS version/project regeneration or comments; no change to the released Mac binary. |
| `da422c07d` Companion: regenerate Xcode project after rebasing on origin/master | Skip: iOS version/project regeneration or comments; no change to the released Mac binary. |
| `0caa0c97c` Companion: bump iTerm2 Buddy to version 1.2, build 1 | Skip: iOS version/project regeneration or comments; no change to the released Mac binary. |
| `19a26e06a` Support dropping a tab into a collapsed tab group | Skip: tab-group implementation and associated drag tests are absent in the fork. |
| `828ce040c` pwmplugin: derive product path from toolchain instead of hardcoding | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `c9d98cea2` pwmplugin: rebuild universal adapter binaries | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `fb66994c0` Fix build errors from newer Xcode/Swift 6.2 toolchain | Equivalent: fork already has explicit captures, handled async writes and unsupported Metal-format fallback. |
| `90d99fd37` Rebuild native dependency artifacts for new Xcode toolchain | Adapt: rebuild retained native dependencies for Xcode 27.2 and arm64 release; no upstream binary/submodule import. |
| `111291852` Ollama: native API provider, discovery, and AI-chat hardening | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `caf289d41` Fix filter showing all lines when refining an in-progress search | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `2adc44ca4` Don't offer Claude Code upsell during app termination | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `769fb4a67` Set Metal drawable timeout on the main thread only | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `78dffc2f7` Fix crash clicking the bookmark button on a command | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `49de2b517` Don't crash marking a dynamic profile rewritable | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `14d64bd21` Use synchronous=NORMAL for restorable-state SQLite | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `a804fab2c` Skip re-saving unchanged grids via a content generation counter | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `8b12ad481` AI presets: rename the Ollama OpenAI-compatible preset to a generic local one | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `1c71cd978` Workgroup toggles: derive button state from the live session flag | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `0cfbd7eaa` Drop default shift-cmd-X from Notify on Status Change | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `97baa31c4` Restore modifyOtherKeys state on session restoration | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `4915720d4` Add regression coverage for the batched-OSC-4 report livelock | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `40f30767b` Don't reload the profile for every tmux pane-title update | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `4f979134d` Reserve the workgroups toolbar in tmux pane sizing | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `623ecbfab` Build librailroad_dsl with a modern deployment target | Skip: librailroad_dsl removed. |
| `a256b5f63` Rebuild sign_update as a universal binary | Skip: Sparkle updater and sign_update no longer used; no removed updater dependency restored. |
| `c2a32ea4b` Git toolbar item: right-click Copy and drag the branch name | Defer optional feature: toolbar copy/drag, About redesign, new window style/location lock, CLI output/routing or tab menu action; no existing bug left behind. |
| `fbaa610a0` Fix notification permission crash (EXC_BAD_ACCESS in invokeAllPendingCompletions) (#740) | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `23807caf3` ✨ feat(about-window): follow system theme with live updates (#632) | Defer optional feature: toolbar copy/drag, About redesign, new window style/location lock, CLI output/routing or tab menu action; no existing bug left behind. |
| `e3035a7f6` Add newly-extracted XIB strings to their catalogs | Skip wholesale catalog import: preserve fork Settings layout and Chinese localization; touched retained strings checked separately. |
| `43b5f05ef` Keep the code string catalog out of Xcode's build-time sync | Skip wholesale catalog import: preserve fork Settings layout and Chinese localization; touched retained strings checked separately. |
| `1ff09d451` Extract new strings into Localizable catalog | Skip wholesale catalog import: preserve fork Settings layout and Chinese localization; touched retained strings checked separately. |
| `4b51d23c0` Translate new strings into de, ja, pt-BR, ru, zh-Hans | Skip wholesale catalog import: preserve fork Settings layout and Chinese localization; touched retained strings checked separately. |
| `685efb37c` Add pre-commit hook blocking untranslated new strings | Skip wholesale catalog import: preserve fork Settings layout and Chinese localization; touched retained strings checked separately. |
| `c8463d6ab` Fix About window credits sizing and appearance-callback ordering | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `29fa4d33e` Say “Below” in tab menus when the tab bar is vertical | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `a30762d17` Fix crash from autoreleased array of stack blocks in tab context menu | Skip: fork tab menu has no autoreleased stack-block array. |
| `efbb9553a` Fix Kitty base-layout key reporting (#741) | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `0e17f7774` Omit zero base-layout key in shifted Kitty reports | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `03e62379a` Add AI Usage workgroup toolbar item | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `0c86531f0` Move Tab Left/Right move the tab, not its whole group | Skip: tab-group implementation and associated drag tests are absent in the fork. |
| `9df974b2c` Harden AI Usage toolbar item after review | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `a23c8c3af` Add Python API for tab groups | Skip: tab-group implementation and associated drag tests are absent in the fork. |
| `20b455b5a` Populate CellStyle.url for OSC 8 hyperlinks in the API | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `014df33c7` Decouple posix_spawn session launch from TCC disclaim; fix its PATH search and signal reset | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `261d575d2` Treat absent Kitty placeholder image-id MSB as zero (#13027) | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `063cdb062` Run CI on the Xcode 27 preview runner to match committed toolchain | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `ca4748e39` Disable xcode-tests CI job until the Xcode 27 build mismatch resolves | Skip upstream-only documentation/test infrastructure/release bookkeeping; use fork build, focused tests and release workflow. |
| `a9cdabb62` Fix blank Screen popup when Main Screen is selected | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `a16fbcae8` Make a tab opened from a link in a grouped browser tab join that group | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `812d43159` Fix stale tab shortcut numbers after a group reorder | Skip: tab-group implementation and associated drag tests are absent in the fork. |
| `edb295b98` Fix crash saving a debug log containing an unpaired surrogate | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `fcc31e59d` Verify uv's TLS against the system trust store | Skip: iTermUvCommand removed. |
| `152b74ee4` Add interactive mode to shell-script execution in pidinfo | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `c19fece23` Honor $CLAUDE_CONFIG_DIR when installing the Claude Code hook | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `583839032` Fix crash on an OSC 8 hyperlink containing an emoji | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `2e78c185a` Clear stale double-width/double-height line attributes (#13055) | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `419487eb4` Reveal a join-all-spaces hotkey window on the current space | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `cc572deb2` Fix a tab-drag test hanging the whole ModernTests suite | Skip: tab-group implementation and associated drag tests are absent in the fork. |
| `65372f1d2` Fix the five ModernTests failures the hang was hiding | Skip: AI preset/localization hygiene and new SetWindowFrame tests refer to absent features; selected terminal tests use expectations. |
| `f0a5b09a8` Add a -parallel option to run_tests.expect | Skip upstream-only documentation/test infrastructure/release bookkeeping; use fork build, focused tests and release workflow. |
| `db1ce26aa` Stop external attributes leaking past their run in the API | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `50363ae0b` Fix stale Kitty image when retransmitting under a reused image id (#13028) | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `472a15465` Add a Centered, No Title Bar window style. Issue 13043 | Defer optional feature: toolbar copy/drag, About redesign, new window style/location lock, CLI output/routing or tab menu action; no existing bug left behind. |
| `670502bb2` Expedite SSH conductor side effects so they escape background batching | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `e54e01d4c` Fix deferred side-effect flushes never being armed, and stale timers after a session becomes visible | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `32450755c` Stop reading whole files on the main thread when pasting (#13024) | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `cee9cc21d` Revert Kitty source-crop normalization on retransmit | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `54cba431c` Fix the tab color reset restoring a color the profile never had | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `a66f730ef` Fix an unreachable arm of handleSideChannelOutput that wrote to the wrong state | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `9ee9751cc` Let a conductor command join a pipeline that is already in flight | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `429b475f0` Clip tab bar accessories rather than hiding them outright | Skip: absent scrollable-tab accessory/scrollOffset implementation. |
| `92b5b854e` Detect localhost via OSC 7 machineID instead of hostname matching | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `eb2992d96` Fix Select Menu Item key bindings losing their menu item when only the keystroke is edited | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `9201b6d93` Add session status to variables | Defer feature: expiring/canonical status and new variables; existing status evaluator fixes ported. |
| `368018c30` Log window minimum sizes and per-view constraint counts | Defer diagnostics-only window constraint logging; no behavior correction. |
| `9724d0ae6` Fix Test Connection reporting success for self-hosted AI models. Issue 13021 | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `941c56834` Fix Test Connection refusing to run for an auto-discover AI model | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `e50701855` List every manual AI model, including one on the default Ollama endpoint | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `dba132dd2` Fix stray glyph ink surviving the clear with the GPU renderer when antialiasing is off | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `4c8d54a8d` Fix flag emoji width and the preconverted-string predecessor merge | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `07b79a4be` Remove obsolete scroll-view dismembering workaround (#763) | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `0c8687976` Avoid redundant Session Status reloads when switching or closing tabs (#749) | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `a6c0e15e7` Remove two Session Status reload tests with environment dependencies | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `1e9e8e153` Open Set Window Title by double-clicking the window name beside the tabs (#733) | Defer feature: window-name-beside-tabs UI and its dependent corrections are absent. |
| `885631fdf` Fix dragging, sizing and squeezing of the window name beside the tabs | Defer feature: window-name-beside-tabs UI and its dependent corrections are absent. |
| `35e05ff3f` Upload every dropped file over ssh integration, not just the first | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `64791fc3c` Fix the paste-options dialog remembering the wrong choice | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `98124626f` Clean up after removing the dismember scroll view workaround | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `dece2b56d` Don't change presentation options while the app is inactive | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `86ce92cd3` Credit Nimanou (nuved) for the right-to-left improvements in the release notes | Skip upstream-only documentation/test infrastructure/release bookkeeping; use fork build, focused tests and release workflow. |
| `424bb2a15` Move the credit for Nimanou (nuved) to the top of the release notes | Skip upstream-only documentation/test infrastructure/release bookkeeping; use fork build, focused tests and release workflow. |
| `96b53e37c` Add Window > Lock Location to pin a window to its display. Issue 13031 | Defer optional feature: toolbar copy/drag, About redesign, new window style/location lock, CLI output/routing or tab menu action; no existing bug left behind. |
| `d2244451b` Use a server this process launched for new sessions. Issue 12106 | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `1acab0d1d` Stop offering to reset key reporting when the shell manages the mode itself. Issue 13032 | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `7e391c4e7` Add the string catalog entries for the Centered, No Title Bar window style. Issue 13043 | Skip wholesale catalog import: preserve fork Settings layout and Chinese localization; touched retained strings checked separately. |
| `943ef3280` Fix the universal build scripts finding no product to lipo | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `b3e73418d` Let a session status say when it stops being true | Defer feature: expiring/canonical status and new variables; existing status evaluator fixes ported. |
| `d4756ce40` it2: add the expiring-status options to set-status | Defer feature: expiring/canonical status and new variables; existing status evaluator fixes ported. |
| `7e85a540f` cc-status: scope turn statuses to the turn | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `6b64d5802` Keep a manually set tab title when the tab label is refreshed | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `f4b87c0d0` Recompute the tab title before observers of an active-session change run | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `9c723df48` Republish a session's title when its tmux formatting changes | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `19525cd35` Remove two no-op statements from the title code | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `49b8bd0ef` Let it2 target the session showing a tmux pane, locally and over SSH integration | Defer optional feature: toolbar copy/drag, About redesign, new window style/location lock, CLI output/routing or tab menu action; no existing bug left behind. |
| `61d194776` Give each shared localizable string one comment | Skip wholesale catalog import: preserve fork Settings layout and Chinese localization; touched retained strings checked separately. |
| `87d255dfc` Translate the new strings, and fix three that were wrong | Skip wholesale catalog import: preserve fork Settings layout and Chinese localization; touched retained strings checked separately. |
| `5ed491d0c` Add Python API support for Session Notes (#764) | Defer feature: Session Notes Python API and newer expand/collapse animation; preserve existing note API. |
| `296452661` Fix Session Note API defects | Defer feature: Session Notes Python API and newer expand/collapse animation; preserve existing note API. |
| `efdb4c58b` Gate Session Note API on protocol 1.20 and fix hide-during-expand | Defer feature: Session Notes Python API and newer expand/collapse animation; preserve existing note API. |
| `5a7aa1726` Stop reloading the Snippets tool when nothing changed | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `8622e64dd` cc-status: support Codex CLI hooks, keeping their turn state in iTerm2 | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `a65edebd7` Treat a trailing newline in send_text as the Return key | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `4cd6e63ba` Don't truncate bodies in parse_ai_wire_log.py by default | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `4ef38be0a` Skip non-BMP bidi mirroring pairs instead of failing | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `94073f9ff` Find Swift stringsdata via xcodebuild's PROJECT_TEMP_DIR in extract_strings | Skip wholesale catalog import: preserve fork Settings layout and Chinese localization; touched retained strings checked separately. |
| `92f00183d` Update translations | Skip wholesale catalog import: preserve fork Settings layout and Chinese localization; touched retained strings checked separately. |
| `f63e43701` Fix two crashes on runs of spacing combining marks. Issue 13073 | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `e81d5c2c4` Make password manager authentication one exclusive choice | Defer feature: new every-open authentication policy and dependent fixes; preserve existing authentication defaults. Existing screen-lock bug ported separately. |
| `ec087cf9b` Keep a skin-toned emoji in one two-column cell. Issue 13079 | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `63538c9c4` Redact directory tracker and other missed session keys in plist sanitizer | Defer optional tooling: new private-plist sanitizer; no sanitizer installed in this fork. |
| `ed001e0bd` Make HDR cursor brightness configurable | Defer feature: HDR cursor brightness; preserve current cursor defaults. |
| `8242815bc` Keep tmux panes' key encoding stable across a detach (issue 13076) | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `52fdf260e` Handle the command selector an IME hands back after committing. Issue 13030 | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `800dcf986` Sanitize session names used in archive and autolog filenames. Issue 13094 | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `a2e47cc5c` Re-enable the seven skipped PSMTabGroupDragTests | Skip: tab-group implementation and associated drag tests are absent in the fork. |
| `0fc027158` Track Package.resolved | Skip upstream package lock replacement; retain fork-specific package graph and resolved versions. |
| `0040f1e45` Add CLAUDE.md rule against computer use and accessibility APIs | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `2f5717b0c` Give the wrap-dropped-filename-in-quotes setting its own tooltip. Issue 13086 | Skip: incorrect upstream tooltip is not present in fork XIB/catalog. |
| `660c95167` Move Show Clippings to cmd-shift-opt-G so cmd-shift-= makes text bigger again. Issue 13022 | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `cecaae04d` Treat a %exit line inside a tmux response block as data on tmux 1.9 and later | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `21302a410` CLAUDE.md: mark the legacy iTerm2XCTests target as deprecated | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `9e56e95d9` Don't read past the end of the margin renderer's vertex buffer. Issue 12604 (#776) | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `52f95bb02` Make Open Selection as URL work on scheme-less links (issue 13092) | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `642e677c7` Have the margin renderer's vertex buffer initializer return its vertex count | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `f0a2fe4e3` 3.7.4beta1 release notes | Skip upstream-only documentation/test infrastructure/release bookkeeping; use fork build, focused tests and release workflow. |
| `8b865198a` Open files in Xcode without relying on the xcode-select shim. Issue 13091 | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `c54b27dad` Only animate large cursor movements shortly after user input. Issue 13034 | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `a2709a912` Translate new and stale strings in the code catalog | Skip wholesale catalog import: preserve fork Settings layout and Chinese localization; touched retained strings checked separately. |
| `91411f536` Add the BDSM and SCP escape sequences for controlling right-to-left reordering (issue 13102) | Defer feature: new cell/window frame queries and BDSM/SCP control sequences; existing terminal protocols preserved. |
| `9daabc7d7` Port the legacy iTerm2XCTests to ModernTests in Swift and delete the old targets | Skip upstream-only documentation/test infrastructure/release bookkeeping; use fork build, focused tests and release workflow. |
| `f728dd7c8` Actually enable WAL mode in the graph database | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `603a9a16e` Mark the optional iTermPythonArgumentParser properties nullable | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `1f95cec9c` Skip the merged DWC_RIGHT when the cursor sits on the predecessor's spacer | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `709472649` Encode editor URL query values exactly once in Semantic History | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `eb8ea03e4` Pad screen char arrays with null cells instead of the EOL code | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `e71838655` Send the meta byte for Option+key in the termkey key mapper | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `710d0f737` Stop a wrapped backward search before the match it already reported | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `754761537` Drop a selection of only nulls when the screen is resized | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `127e2f0c3` Release notes for the Semantic History, CSI u, selection and state-saving fixes | Skip upstream-only documentation/test infrastructure/release bookkeeping; use fork build, focused tests and release workflow. |
| `2e7e76919` Correct the all-null selection check's comment and add resize tests | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `9660b6449` Add expected-failure tests for Semantic History editor URL values | Covered: final Semantic History URL regression expectations adapted with later 762644229 fix. |
| `762644229` Send MacVim an escaped file URL and TextMate the raw path | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `f1830a23e` Correct the Semantic History release note | Skip upstream-only documentation/test infrastructure/release bookkeeping; use fork build, focused tests and release workflow. |
| `21b438039` Add backward search tests with the match in the final cell | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `73e1d7d53` Make the shell environment reply nullable and let the composer recover from a failed PATH read | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `ba0042135` Run password manager adapters with the user's shell PATH | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `5c7a35dd4` Make the Bitwarden integration report real errors and recover from rejected sessions | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `afe4cc2f1` CLAUDE.md: drop the note about the deleted iTerm2XCTests target | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `6443852b0` Fall back to a GitHub Pages mirror of the companion shard map | Port/adapt: resolver mirror fallback, error propagation and Mac diagnostics; shared-package and Mac regression verification required. |
| `fe54bd10c` Make Find treat cells the cursor skipped over as spaces | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `c248641ea` Align the password manager's Working label with its Cancel button's baseline | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `7c0477c87` Recognize cc-status hook commands that use $HOME, ~, or a wrapper | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `d2de7d6a4` Keep user vars and shell integration state set while a tmux pane opens. Issue 13006 | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `b563be9a5` Keep the stoplight hotbox from covering clickable toolbars and status bars. Issue 13100 | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `2765edb79` Fix a crash and oversized panes when the API sets a layout with a browser session (#783) | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `6b1f131bf` Update the AI model catalog to current vendor lineups | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `8f3ecc772` Fix a race that could drop a new session's first tokens | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `c546542c2` Fix live AI harness failures caused by vendor changes | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `d25a52cab` Make live harness tab title corpus tests opt-in | Skip: absent AI wizard, live model harness and AI-agent menu-bar status surfaces. |
| `1c011635a` Fix crash when a new tab joins the current tab's group | Skip: tab-group implementation and associated drag tests are absent in the fork. |
| `253e423a9` Keep it2 from relaunching iTerm2 while it quits | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `ed7be8179` Fix histogram sampler weight overflow after weeks of uptime. Issue 13103 | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `df780a158` Stop old key bindings from hijacking the A key in physical-key mode | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `4acdd013c` Let undo close restore sessions from their archives | Defer feature: archive-based Undo Close replacement; retain existing Undo Close and no migration prompt. |
| `ff6c66fa1` Fix crash loops in the window state database from overlapping saves | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `132c8d805` Fix heap corruption from a stale find indicator range | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `acbd9d7bd` Fix a crash from NSFont keys in the Metal font ID bijection | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `51952da84` Fix a crash importing all settings that change a secure setting | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `49ebe2949` Skip sockets when exporting all settings and data | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `f99bea55a` Explain and exit when the AI model catalog can't be loaded | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `57978e823` Explain and exit instead of crashing on other missing bundle resources | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `dd65a6b9d` Don't load the Settings window when the app hotkey is pressed | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `dbf0fa199` Keep the titlebar accessory nanny away from windows without a title bar | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `03c6d1c3b` Fix a crash Cmd-hovering over a composer autosuggestion | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `75e03729b` Don't trust value types in Dynamic Profiles files | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `72707c178` Don't split a pane that left the window during an async split | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `4a5efa158` Don't let tab accessibility elements outlive their cell unsafely | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `59ef5b3c0` Keep the grid size finite when a font measures as zero | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `04f4b0f23` Don't unwrap a nil iTermController when GlobalJobMonitor starts | Skip: GlobalJobMonitor removed. |
| `77471ec98` Keep Metal frame statistics alive as long as the frames using them | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `b7821dea8` Skip smart selection rules that have no regex | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `23ae5a75b` Take the texture pool's lock when the power manager empties it | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `1f58a4f5c` Don't let a skipped nanny update swallow later ones | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `18893448f` Fix frame of views in settings>general>ai>prompts | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `7ade1ebf3` Keep a symlinked settings.json when writing the Claude Code hook. Issue 13098 (#775) | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `4c75d8536` Preserve -suite when relaunching after importing settings | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `101fe2302` Keep the companion connection alive while a modal freezes the main queue | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `b387e2980` Let a paired phone reconnect while a modal freezes the main queue | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `178f35e0d` Publish modal warnings to a registry that other threads can answer | Defer feature: remotely answering Mac modals; retained link/ack/reconnect/stall protection ported without remote-modal protocol. |
| `df02f4859` Tell the phone which alerts are showing and whether the Mac is blocked | Defer feature: remotely answering Mac modals; retained link/ack/reconnect/stall protection ported without remote-modal protocol. |
| `cd1ee39b4` Show and answer the Mac's alerts in iTerm2 Buddy | Defer feature: remotely answering Mac modals; retained link/ack/reconnect/stall protection ported without remote-modal protocol. |
| `b871b222c` Fix review findings in the companion modal-alert work | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `50b2f737d` Let the phone fill in the values a warning asks for | Defer feature: remotely answering Mac modals; retained link/ack/reconnect/stall protection ported without remote-modal protocol. |
| `08e98eaf0` Fix a crash listing sessions for the phone when a tab has no title yet | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `cd045f83b` Only interrupt the phone for alerts that block the Mac or concern the session on screen | Defer feature: remotely answering Mac modals; retained link/ack/reconnect/stall protection ported without remote-modal protocol. |
| `d549a3d53` Let the phone enter secrets, set an accessory checkbox, and skip Mac-only buttons | Defer feature: remotely answering Mac modals; retained link/ack/reconnect/stall protection ported without remote-modal protocol. |
| `8303ed007` Let the phone answer the password prompt and the scp password prompt | Defer feature: remotely answering Mac modals; retained link/ack/reconnect/stall protection ported without remote-modal protocol. |
| `4bf61620b` Add a debug menu item that shows the password prompt from a main-queue block | Defer feature: remotely answering Mac modals; retained link/ack/reconnect/stall protection ported without remote-modal protocol. |
| `76ac80a6d` Convert most plain NSAlerts to iTermWarning so the phone can answer them | Defer feature: remotely answering Mac modals; retained link/ack/reconnect/stall protection ported without remote-modal protocol. |
| `ebe58b911` Don't report a cancel after an accepted natural-language query prompt | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `bc702cf87` Remove the debug menu items for freezing the main queue | Defer feature: remotely answering Mac modals; retained link/ack/reconnect/stall protection ported without remote-modal protocol. |
| `e26c73321` Act only on the phone's current connection, and close ones it gives up on | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `0a283a1a4` Refuse scroll-wheel reports during a stall and deliver stream acks off the main actor | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `5470de343` Fix review findings in how warnings are published and answered | Defer feature: remotely answering Mac modals; retained link/ack/reconnect/stall protection ported without remote-modal protocol. |
| `b509b976a` Hide buttons that only make sense at the Mac from the phone | Defer feature: remotely answering Mac modals; retained link/ack/reconnect/stall protection ported without remote-modal protocol. |
| `920fb6e13` Fix review findings in how the phone answers and tracks Mac alerts | Defer feature: remotely answering Mac modals; retained link/ack/reconnect/stall protection ported without remote-modal protocol. |
| `db38c6dca` Refuse a second answer to an alert that was already answered, and stop storing room secrets at unpair | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `29f7b8d62` Restore the braces lost rebasing the pairing controller onto master | Equivalent: adapted pairing controller has balanced reconnect branches; Development build and transport tests pass. |
| `673520779` Keep verified OSC 7 locality from being overridden by stale third-party reports | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `13fb5d34a` CLAUDE.md: use iTermWarning rather than NSAlert so the phone can answer alerts | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `e4fb0227e` Use a secure text field for the AI API key prompt | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `58717be72` Make offline shell integration install work without bash | Skip: removed shell-integration installation surface. |
| `510d5e93d` Warn when another instance is using the same settings domain | Defer optional feature: same-settings-domain instance warning and test-host exemption; existing -suite isolation remains. |
| `1271f1b74` Translate remaining untranslated catalog strings | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `636600552` Remove the incorrect claude- suite rule from CLAUDE.md | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `c77dbd257` Add floating panes | Defer feature: floating panes and archive restoration; generic filtered tmux identity correction ported independently. |
| `b0065ee05` Don't warn about another running instance in a test host | Defer optional feature: same-settings-domain instance warning and test-host exemption; existing -suite isolation remains. |
| `087cbfe03` Tell the TUI safety check which session it is judging and when watches fire | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `e1f5e2f3d` Split environment entries on a literal '=' (#789) | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `52c8dab89` Hotkey window: skip the resign-active wait when nothing could flash | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `601c0a260` Let a manual AI model choose which API key it sends | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `09894ed6e` Keep Session Note open when shown from Open Quickly | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `d84fbcbd7` Substitute the user's name and email placeholder in the crash report message again | Skip: UKCrashReporter and its XIB removed. |
| `1ce6f12b8` Remove a leftover merge conflict marker from the release notes | Skip upstream-only documentation/test infrastructure/release bookkeeping; use fork build, focused tests and release workflow. |
| `d5b299707` Honor tmux new-window -d in tmux integration. Issue 13112. | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `9d5e5b4ea` Report BDSM as permanently reset when right-to-left support is off (issue 13102) | Defer feature: new cell/window frame queries and BDSM/SCP control sequences; existing terminal protocols preserved. |
| `cd249d48f` Menu bar status item for busy AI agents | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `9bbe6a975` Move the menu bar item to Settings and show a bug on evaluation errors | Skip: absent AI wizard, live model harness and AI-agent menu-bar status surfaces. |
| `2437bfba6` Turn off “Add period with double-space” in iTerm2. Issue 13123. | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `1ba7be767` Turn off automatic spelling correction, capitalization, and smart quotes and dashes | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `4478e9ab5` Keep help popovers from clipping their last line | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `94a40e856` Stop leaking the tmux window-change ignore counter. | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `72c85bfd1` Archive to a default folder when none is set. Issue 12980 | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `cf33c462d` Leave cc-status hook commands that also run the user's programs | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `9f17e76ef` Make Voice Control corrections replace text instead of appending | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `20c5b0502` Keep session mentions linkable when markdown pairs their underscores | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `5c9421171` Remove obsolete macOS 12.x compatibility code (#738) | Defer cleanup: availability-code pruning only; preserve fork macOS 12.4 baseline. |
| `0ad0016ca` Remove unused macOS 11 deprecation strings | Defer cleanup: availability-code pruning only; preserve fork macOS 12.4 baseline. |
| `b5f4046ec` Tag AI tab-title corpus records by session and keep reworded titles | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `9e65c39eb` Add --format to it2 session list. Issue 13088. | Defer optional feature: toolbar copy/drag, About redesign, new window style/location lock, CLI output/routing or tab menu action; no existing bug left behind. |
| `964a75d0f` Skip tests that put windows on screen unless ITERM2_ONSCREEN_TESTS=1 | Skip upstream-only documentation/test infrastructure/release bookkeeping; use fork build, focused tests and release workflow. |
| `e798b2297` Let each profile choose the sound its bell makes | Defer feature: per-profile custom bell sound and dependent validation; existing system bell retained. |
| `dd0e08275` Play custom bell sounds as alerts through System Sound Services | Defer feature: per-profile custom bell sound and dependent validation; existing system bell retained. |
| `49936d3a5` Support the Program Status Protocol (OSC 7501) and add done/error statuses | Defer feature: OSC 7501 task-status protocol and dependent coalescing/rate limiting; absent in fork. |
| `f5147e4aa` Remove dangling CompanionLoopbackTransport.swift references from the project | Equivalent: new loopback test helper is discovered by synchronized test group; no dangling explicit PBX reference. |
| `af6cfbd3f` Add missing translations and fix stale localizations | Skip wholesale catalog import: preserve fork Settings layout and Chinese localization; touched retained strings checked separately. |
| `a63ed419c` List OSC 7501 tasks in Session Status and notify per task | Defer feature: OSC 7501 task-status protocol and dependent coalescing/rate limiting; absent in fork. |
| `120de33b4` Improve clipboard image pasting and upload performance over SSH | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `df0010277` Add an NSOutlineView reload that doesn't leak disclosure buttons | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `87560f65e` Cap the Script Console's finished entries at 200 | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `a82b7776e` Stop a finished Script Console entry from observing the API | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `93f4367f6` Stop the job tree from leaking disclosure buttons on every tab switch | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `bedd2b5b6` Update the Snippets tool's comments about leaking reloads | Skip upstream-only documentation/test infrastructure/release bookkeeping; use fork build, focused tests and release workflow. |
| `5c60f1323` Keep Script Console entries alive while their script is | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `1fc57e2d2` Run the tests on a VM instead of this Mac | Skip upstream-only documentation/test infrastructure/release bookkeeping; use fork build, focused tests and release workflow. |
| `4ef885ba2` Answer iTerm2's first-run update prompt on test VMs | Skip upstream-only documentation/test infrastructure/release bookkeeping; use fork build, focused tests and release workflow. |
| `3535b2ea8` VM tests: cancel a run that goes quiet, and run any command after -- | Skip upstream-only documentation/test infrastructure/release bookkeeping; use fork build, focused tests and release workflow. |
| `7ce037e14` VM tests: clean up after hung runs, and free a lock whose connection died | Skip upstream-only documentation/test infrastructure/release bookkeeping; use fork build, focused tests and release workflow. |
| `bc36feb8f` Rework Focus Follows Mouse so it stops taking focus from fields in a pane | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `3d5cb5844` Add tools for agents to do hands-on QA on a test VM | Skip upstream-only documentation/test infrastructure/release bookkeeping; use fork build, focused tests and release workflow. |
| `b94716f8d` VM tests: require --host instead of defaulting to vm1 | Skip upstream-only documentation/test infrastructure/release bookkeeping; use fork build, focused tests and release workflow. |
| `e4edf85c1` Stop leaking the multiserve launch-request buffer. (#793) | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `f74abc16e` Add Rename Tab to the tab context menu | Defer optional feature: toolbar copy/drag, About redesign, new window style/location lock, CLI output/routing or tab menu action; no existing bug left behind. |
| `da5587f60` Point translation docs at the tracked string catalog | Skip wholesale catalog import: preserve fork Settings layout and Chinese localization; touched retained strings checked separately. |
| `5964ff231` Only apply appearance settings from Instant Replay recordings | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `119e41381` Fix crash when a Set Profile Setting trigger fires | Skip: absent Prevent Sleep and Set Profile Boolean trigger feature. |
| `6588dbd1b` Fix crash when a tmux window becomes key after detaching | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `66c8074f2` Wire the Prevent Sleep checkbox to settingChanged: | Skip: absent Prevent Sleep and Set Profile Boolean trigger feature. |
| `7b5f64d9d` Re-take the Prevent Sleep assertion after Restart Session and Undo Close | Skip: absent Prevent Sleep and Set Profile Boolean trigger feature. |
| `5d27a4e7b` Keep a manual model's auth on its economy variant | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `93cf46a0f` Truncate hidden rows and dequeue removed messages on AI chat delete | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `7bf302da1` Defer AI chat watcher reconciliation until session restoration finishes | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `35ca9f4f8` Run the AI Usage command with the user's shell PATH | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `b48184b46` Do not treat acknowledging a status as a change for Notify on Status Change | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `fb62f2153` Make Opt-Return and Opt-Shift-Return send in the Cockpit composer | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `c977684b4` Never put a native session into a tmux tab as a floating pane | Defer feature: floating panes and archive restoration; generic filtered tmux identity correction ported independently. |
| `ef6d5c1e7` Rebuild it2 to pick up session list --format and new status help | Equivalent: arm64 it2 rebuilt from fork sources, excluding deferred CLI features. |
| `3d8766648` Keep observing variables an async evaluation reads late | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `f29249394` Cancel an AI chat turn when its message is deleted | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `c4a5d8175` Redact AI custom header values and keys from debug and wire logs | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `7b98b5378` Keep each color of a mid-word SGR split on the legacy renderer | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `bc0e53816` Keep a cleared screen in place when restoring a session | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `92c692e47` Fix offline shell integration install hanging for zsh | Skip: removed shell-integration installation surface. |
| `db34734ba` Fix crashes acting on tmux windows left open after detaching | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `23246de5f` Close only the detached tmux windows that asked when answering Always | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `7ba984c85` Keep AI chat timers and watches from reaching the LLM under the AI lockout | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `e5683af8d` Treat a non-string bell sound in a profile as the system alert sound | Defer feature: per-profile custom bell sound and dependent validation; existing system bell retained. |
| `236baa8f8` Pass the shell's CLAUDE_CONFIG_DIR to the AI Usage command | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `f474bbe54` Revoke password manager authentication on screen lock without its window | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `629174b29` Send only the selected text from the Cockpit composer | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `c5d4d5bbb` Stop the companion wizard from asking for a key the AI model won't use | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `480622623` Keep AI chat links and watches across a quit that restores windows | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `38236b580` Keep the Cockpit composer's chips and caret when the outline changes | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `ab5c56888` Keep focus and floats right for a filtered tmux pane on layout change | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `20e9d3ebd` Load triggers that have no regex instead of crashing | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `da38f0acc` Give same-named files in one SSH upload batch distinct remote names | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `12d6d26fd` Reset custom headers and API key choice when a model preset is chosen | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `b73ed07d0` Run the AI safety check migration at launch so it never undoes a new choice | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `a31d7af1b` Send a vendor's key automatically only to that vendor's own host | Skip: absent AI wizard, live model harness and AI-agent menu-bar status surfaces. |
| `fc2ca3f43` Let a click replace Cockpit chips from clicked rows that are now hidden | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `54596b751` Size Companion wizard choose-mode details to fit their text | Skip: absent Companion wizard; retained classic pairing controller used. |
| `70c88ebeb` Keep session.path on the remote directory when the local cwd is polled | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `eb2532c6e` Show the AI lockout alert for Engage AI in the Composer | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `8f93654fa` Let the local cwd update session.path again after leaving ssh | Skip net-reverted SSH-exit heuristics; retain stable final OSC 7 locality behavior. |
| `9b1e88fec` Send the OpenAI key automatically only to Azure's AI service hosts | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `40482977f` Translate the Companion wizard strings added for AI model setup | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `7e356f272` Translate the AI key strings and fix two zh-Hans Companion explanations | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `cc943310c` Coalesce OSC 7501 reports so a flood cannot swamp the main thread | Defer feature: OSC 7501 task-status protocol and dependent coalescing/rate limiting; absent in fork. |
| `e8017c3bc` Update session.path when the local shell returns from ssh without a cd | Skip net-reverted SSH-exit heuristics; retain stable final OSC 7 locality behavior. |
| `34b5bcc6c` Give the AI key hint room for its longest translation | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `5d9d74a4f` Don't overwrite an unparseable Claude Code settings.json on install | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `3aaa1a718` Hold a remote session.path only while ssh's process group is in the foreground | Skip net-reverted SSH-exit heuristics; retain stable final OSC 7 locality behavior. |
| `dbe76fdd4` Bound AI Usage command memory and kill its whole process group | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `51926787e` Keep one rate-limit timer per program status notifier | Defer feature: OSC 7501 task-status protocol and dependent coalescing/rate limiting; absent in fork. |
| `1d2523ffd` Expand {{FILE}} in AI suggestions with the whole filename | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `0ebb2a7f5` Keep AI chat timers when a chat is unlinked from its session | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `c51fe9110` Keep pinned tabs out of unpinned groups on Move Tab Left/Right | Skip: tab-group implementation and associated drag tests are absent in the fork. |
| `1232ad975` Keep AI chat watches on tmux panes across a relaunch | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `9cf0d68fd` Keep AI chat watches on tmux panes across a quit that restores windows | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `550bf1748` Keep the Claude Code hook when the config dir is an alias of ~/.claude | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `95c1a8699` Cancel only the stopped AI request, not another chat's | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `4e16e4a10` Revert the session.path ssh-exit heuristics built on the F-103 fix | Skip net-reverted SSH-exit heuristics; retain stable final OSC 7 locality behavior. |
| `d5e435855` Show the basic-auth sheet instead of prompting in every-open mode | Defer feature: new every-open authentication policy and dependent fixes; preserve existing authentication defaults. Existing screen-lock bug ported separately. |
| `582002ffb` Type a space instead of “. ” for double-space period substitution | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `d5bcfdf18` Don't show the locale prompt as a sheet on an unseen hotkey window | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `45d2c6eed` Restore an archived floating pane as a float on Undo Close | Defer feature: floating panes and archive restoration; generic filtered tmux identity correction ported independently. |
| `9a370d2e2` Keep tmux floats in place on attach by pinning window sizes first | Defer feature: floating panes and archive restoration; generic filtered tmux identity correction ported independently. |
| `2a7d798d4` Hide password manager accounts until an every-open prompt succeeds | Defer feature: new every-open authentication policy and dependent fixes; preserve existing authentication defaults. Existing screen-lock bug ported separately. |
| `5e9018b0a` Recover from an SSH Integration connection that dies abruptly | Port/adapt: retained functionality; implementation and verification recorded in batches above. |
| `3de66d3b5` Keep @-mention chips on the text baseline | Skip: removed AI/browser/Cockpit/agent-hook product surface. |
| `5a39e1e14` Cancel Companion wizard setup when the wizard is closed | Skip: absent Companion wizard; retained classic pairing controller used. |
| `0f0dec8ae` Authenticate every open of the standalone password manager window | Defer feature: new every-open authentication policy and dependent fixes; preserve existing authentication defaults. Existing screen-lock bug ported separately. |
| `aebf95a06` Stop localizing the Get Info version string | Skip: InfoPlist.xcstrings absent and local overlays do not override bundle version. |
| `7ce456b98` Keep a manual model's economy requests on the manual model | Skip: removed AI/browser/Cockpit/agent-hook product surface. |

#### Master Follow-Up Inventory

Reviewed against the same old cursor: 931 commits; 345 exact shared commits use the stable dispositions above. The remaining 586 are classified below, including branch-equivalent fixes. Defer means retain a named candidate for a separate next-stable review, not claim its patch is applied. The release cursor advances only to the stable release hash.

| Commit / subject | Disposition |
| --- | --- |
| `498eb0bf9` Keep the manual size of centered hotkey windows. Issue 13125. | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `3fdf2ae81` Add a Python API to hide a browser session's toolbar | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `2c11be0df` Add Python API to run JavaScript in browser sessions | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `8aae4e76e` Translate the Manage Permissions button in Settings > General > Magic | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `fe8cbff71` Add submenu and visible_when to Python API context menu providers | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `b134abde9` Add nushell shell integration (#795) | Skip removed shell installer/scripts; no submodules restored. |
| `066eb8749` Add type annotations to the Python API | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `49c77281c` Fix bugs and add guards in the Python API | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `37252d92a` Add release notes for Python API type annotations and fixes | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `22833b580` Bump the Python API module version to 2.29 | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `9af57e38c` Embed the current it2.py in the nushell shell integration script | Skip removed shell installer/scripts; no submodules restored. |
| `613bd64f3` Translate the nushell shell integration strings | Skip removed shell installer/scripts; no submodules restored. |
| `ebda02119` Join windowed and connected selection lines in the Python API | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `069b6e0dd` Bump the Python API module version to 2.30 | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `7be73ffc5` 3.7.5 | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `d6e2da153` Fix crash when a Set Profile Setting trigger fires | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `7f86879da` Fix crash when a tmux window becomes key after detaching | Already present: the fork guards detached tmux select-window earlier in the method. |
| `0f4c69c52` Wire the Prevent Sleep checkbox to settingChanged: | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `065289754` Re-take the Prevent Sleep assertion after Restart Session and Undo Close | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `8e90f1c2c` Keep a manual model's auth on its economy variant | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `c79ba5cf2` Truncate hidden rows and dequeue removed messages on AI chat delete | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `3a71b917b` Defer AI chat watcher reconciliation until session restoration finishes | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `7b3b765a3` Run the AI Usage command with the user's shell PATH | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `84dc60625` Do not treat acknowledging a status as a change for Notify on Status Change | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `94a74f336` Make Opt-Return and Opt-Shift-Return send in the Cockpit composer | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `eb7f13278` Never put a native session into a tmux tab as a floating pane | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `4d355f604` Rebuild it2 to pick up session list --format and new status help | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `5b2327dd0` Keep observing variables an async evaluation reads late | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `75dbc2d9c` Cancel an AI chat turn when its message is deleted | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `cd6120e1c` Redact AI custom header values and keys from debug and wire logs | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `e91f5de60` Keep each color of a mid-word SGR split on the legacy renderer | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `9db0ed4b7` Keep a cleared screen in place when restoring a session | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `dd51894a4` Fix offline shell integration install hanging for zsh | Skip removed shell installer/scripts; no submodules restored. |
| `3fe71fd29` Fix crashes acting on tmux windows left open after detaching | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `6f5030ecb` Close only the detached tmux windows that asked when answering Always | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `f3021bb83` Keep AI chat timers and watches from reaching the LLM under the AI lockout | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `30a3a507a` Treat a non-string bell sound in a profile as the system alert sound | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `12f3f1c40` Pass the shell's CLAUDE_CONFIG_DIR to the AI Usage command | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `d3ba85077` Revoke password manager authentication on screen lock without its window | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `f96c57449` Send only the selected text from the Cockpit composer | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `be89e2f85` Stop the companion wizard from asking for a key the AI model won't use | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `850d060c0` Keep AI chat links and watches across a quit that restores windows | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `2821a9cb0` Keep the Cockpit composer's chips and caret when the outline changes | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `5496b9a85` Keep focus and floats right for a filtered tmux pane on layout change | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `627b18631` Keep session.path on the remote directory when the local cwd is polled | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `e170f0674` Load triggers that have no regex instead of crashing | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `690032eb8` Give same-named files in one SSH upload batch distinct remote names | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `fd89b9e2d` Reset custom headers and API key choice when a model preset is chosen | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `865da6d6f` Run the AI safety check migration at launch so it never undoes a new choice | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `ae970a680` Send a vendor's key automatically only to that vendor's own host | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `f7fd24bd8` Let a click replace Cockpit chips from clicked rows that are now hidden | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `0583490cd` Size Companion wizard choose-mode details to fit their text | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `759b8500b` Show the AI lockout alert for Engage AI in the Composer | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `0eeb67562` Let the local cwd update session.path again after leaving ssh | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `353fd51ce` Send the OpenAI key automatically only to Azure's AI service hosts | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `b0e299432` Translate the Companion wizard strings added for AI model setup | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `1a72d1b91` Translate the AI key strings and fix two zh-Hans Companion explanations | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `257d58637` Coalesce OSC 7501 reports so a flood cannot swamp the main thread | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `0aad5c5f1` Update session.path when the local shell returns from ssh without a cd | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `fe14e5340` Give the AI key hint room for its longest translation | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `f8363613b` Don't overwrite an unparseable Claude Code settings.json on install | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `ab6f00d72` Hold a remote session.path only while ssh's process group is in the foreground | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `c9c59d8ff` Bound AI Usage command memory and kill its whole process group | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `f084c3584` Keep one rate-limit timer per program status notifier | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `25c6932e7` Expand {{FILE}} in AI suggestions with the whole filename | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `465e43122` Keep AI chat timers when a chat is unlinked from its session | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `f18c79a8a` Keep pinned tabs out of unpinned groups on Move Tab Left/Right | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `2096b0066` Keep AI chat watches on tmux panes across a relaunch | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `699d4c2d2` Tell the user when Stop or Disable Orchestration cancels AI chat timers | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `cc952c74e` Keep AI chat watches on tmux panes across a quit that restores windows | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `31a8704c8` Keep the Claude Code hook when the config dir is an alias of ~/.claude | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `01cfccd29` Cancel only the stopped AI request, not another chat's | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `6aa611610` Name the reattached tmux pane's workgroup in a re-bound AI chat watch | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `89eebcaeb` Revert the session.path ssh-exit heuristics built on the F-103 fix | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `9179e15db` Show the basic-auth sheet instead of prompting in every-open mode | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `6a8e134fc` Coalesce title changes so a title flood cannot swamp the main thread | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `61baf0428` Don't show the locale prompt as a sheet on an unseen hotkey window | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `d9c2d852c` Type a space instead of “. ” for double-space period substitution | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `f354788c5` Restore an archived floating pane as a float on Undo Close | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `9b82aed36` Recover from an SSH Integration connection that dies abruptly | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `85963967b` Keep @-mention chips on the text baseline | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `4da67fc7b` Keep tmux floats in place on attach by pinning window sizes first | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `924452ad6` Cancel Companion wizard setup when the wizard is closed | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `9ab9b0e37` Hide password manager accounts until an every-open prompt succeeds | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `d5a2c8ab1` Fix sanitizer gaps for Ollama models, adapter paths, and profile triggers | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `5e6d09a93` Authenticate every open of the standalone password manager window | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `a953a86c7` Fix typos and localization gaps in several user-visible strings | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `2434200e2` Stop localizing the Get Info version string | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `2793f4eb4` Keep a manual model's economy requests on the manual model | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `023d97c2a` Keep text editing shortcuts for an alert's text field | Ported in `046e68195`; see Partial Upstream Master Triage After 3.7.6. |
| `05eec3465` Free each AI request's URLSession, delegate and JSContext | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `d47dfe0bc` Add a regression test for tmux detach releasing Prevent Sleep | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `3932d4608` Never put a native session into a tmux tab as a split pane | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `d226ee413` Return focus to the terminal when a focused session note is hidden | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `15d9b471a` Validate and clamp OSC 1337 SetWindowFrame | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `57695ac60` Don't act on a browser prompt answered after the script timed out | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `524320058` Never send a Llama (Local) chat to the cloud default vendor | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `0d919c1e4` Keep the space between LTR and RTL text when copying part of a bidi line | Ported in `046e68195`; see Partial Upstream Master Triage After 3.7.6. |
| `e2ab0ea8a` Add a regression test that keystrokes typed during a paste stay after it over SSH integration | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `5a89a770e` Add regression tests for focus in iTermWarning text prompts | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `1bd446164` Truncate the restorable state WAL after housekeeping and at quit | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `c050c1048` Don't ask to copy settings at quit just because a migration ran | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `32b4a67c7` Write the nushell shell integration script in order and verify it | Skip removed shell installer/scripts; no submodules restored. |
| `07f4b9dce` Stop Engage AI from crashing in the Cockpit composer | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `959856a7d` Keep long SSH integration framer commands from being cut in two | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `a92f32393` Update a browser tab's minimal theme tint when the page's color arrives | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `de2815c4e` Keep the stoplight hotbox off a browser's navigation bar | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `2df9602e0` Close the Cockpit's session picker when the caret leaves the @-run | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `3c44141a5` Skip closed targets when sending from the Cockpit | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `54a6d4a86` Keep the floating Cockpit panel from covering sheets | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `cf15889c3` Draw the Cockpit composer's placeholder once | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `93a71f8c1` Put @-mention chip edges on whole points from the baseline | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `be95108f4` Keep chips' attachment characters out of Cockpit commands | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `bf9ebba38` Disable session-only composer actions in the Cockpit | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `3a2d9c015` Open the status bar component menu when its proxy icon is clicked | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `6cb62e44e` Don't offer a deleted directory from the status bar proxy icon | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `3a3d99265` Keep text view contents out of the undo-safety debug log | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `5794785e4` Let KeePassXC remember browser basic-auth passwords | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `d89b08f69` Render HTML title tags in pane title bars | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `62df824da` Strip HTML tags from the profile name in window titles | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `9f7bda6f8` Fix saving arrangements and archives that contain hyperlinks | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `c05039165` Re-sign example .its files with the current Developer ID Application certificate | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `fade3b612` Fix the Python API docs build | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `06d3d4aba` Bump Companion marketing version to 1.3 | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `f66776ac9` Export and import Password Manager passwords. Issue 7471. | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `9133cd8fd` Add release notes for 3.7.7beta1 | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `086540d6b` Add a non-interactive beta release script | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `a69a64cfb` Add Password Manager export to 3.7.7beta1 release notes | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `7e7d8a7f7` Sync Password Manager export strings into the string catalog | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `710522de1` Fix release script checks that failed under pipefail | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `7816e7106` PushRelay: recover from dead APNs connections; add APNs health stats | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `b0ceb5999` Sync the website's shell integration submodule on stable release | Skip removed shell installer/scripts; no submodules restored. |
| `cceeed4cb` Add a non-interactive stable release script | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `99ccc1b08` Don't crash highlighting a composer that has no delegate | Ported in `046e68195`; see Partial Upstream Master Triage After 3.7.6. |
| `8130dc8bb` Isolate test hosts' settings and stop hung test runs | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `f855e2a81` Report archive failures and fix more values that broke saved files | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `ca5beae02` Keep launch-time prompts out of test hosts | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `0448a3d47` Make the live refusal scenario opt-in and soften its prompt | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `9e296042e` Push relay: second instance with peer replication; apps fail over | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `ec4517e6b` Fix a main-thread hang waiting on the Metal layer lock. Issue 13139 | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `97616c127` Size tmux panes with each pane's own right gutter | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `5acbbc16e` Keep Auto Layout out of the terminal window. Issue 13118. | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `921bc5a48` Recycle Snippets tool cells and reset their icons on reuse | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `beb7cfbff` Fix Caps Lock reports when it switches input sources. Issue 13136 | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `7593ab037` Make it2dl find bash via env so it works where bash is not in /bin | Skip removed shell installer/scripts; no submodules restored. |
| `3bcfe1b03` Add release note for it2dl bash path fix | Skip removed shell installer/scripts; no submodules restored. |
| `0a2a5f116` Remove a stray conflict marker from the release notes | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `146b2356e` Keep the kitty keyboard protocol across XTMODKEYS requests. Issue 13138 | Ported in `046e68195`; see Partial Upstream Master Triage After 3.7.6. |
| `124020064` Honor disabled ligatures when not preferring speed to ligature support | Ported in `046e68195`; see Partial Upstream Master Triage After 3.7.6. |
| `7e862eb49` Make Hide Activity Indicator also hide the tab progress spinner. Issue 13145. | Ported in `545389446`; see Partial Upstream Master Triage After 3.7.6. |
| `654bb1376` Fix the setting name in the release note for issue 13145. | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `ec52a96ee` Download the v2 shell integration installer | Skip removed shell installer/scripts; no submodules restored. |
| `0e5347359` Release note for the v2 shell integration installer fix | Skip removed shell installer/scripts; no submodules restored. |
| `cd75c6170` Update shell integration for the xonsh installer fix | Skip removed shell installer/scripts; no submodules restored. |
| `b3a3a0b9e` Release note for the xonsh shell integration fix | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `b754d09e6` Fix tab bar corruption when unpinning a tab left of the pin boundary. Issue 13154 | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `0c7dbe4b3` Fix the Make Hyperlink trigger's interpolated default parameter | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `3a97d1ca0` Evaluate trigger-local interpolated parameters without pausing | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `5f1786330` Fix vertically cropped Kitty images in the GPU renderer. Issue 13146. | Ported in `046e68195`; see Partial Upstream Master Triage After 3.7.6. |
| `f29420ae4` Harden the x-man-page URL handler. Issue 5298. | Ported in `046e68195`; see Partial Upstream Master Triage After 3.7.6. |
| `a90c74604` Make tmux divider drags end where the window showed them (#796) | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `7f4ff7397` Send arrow keys and Tab an IME hands back after committing, not just Return and Backspace. Issue 13030 | Ported in `545389446`; see Partial Upstream Master Triage After 3.7.6. |
| `a018081c6` Make browser sessions work in iTerm2 Buddy | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `08b465561` Pick an AI chat @-mention by clicking the session | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `0139844e7` Hide the AI chat submit hint when a long placeholder would overlap it | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `c6eb3aa62` Add QA VM provisioning doc | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `d63ecb667` Translate Lock Location, Rename Tab and the Tab Color label | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `6e30d9277` Translate the menu bar icon settings row | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `d5ec8f42d` Translate the Focus Follows Mouse “even to views” option | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `8a375f43d` Localize the workgroup session Mode popup titles | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `35b2e1c30` Localize the AI-generated name title component | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `3156f1d87` Localize the Set Profile Setting trigger's picker and row text | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `fddf85415` Localize the browser HTTP authentication prompt heading | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `a36c07b74` Localize the AI chat watch consent body and timer bubble | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `9b53b5f4b` Use the custom headers term consistently in Chinese | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `c1d9c67f8` Use ユーザー consistently in Japanese and localize “(unknown)” | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `33bd2d4f9` Translate the OSC 7501 paragraph in the Session Status help | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `d419ccc0e` Address the user formally in the German website permissions strings | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `78933d1a5` Fit the Tags toggle button title in pt-BR and Russian | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `1da68be15` Label the Profiles window's icon-only split buttons | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `c6b1e4dcf` Decode session name and tty in it2 session list | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `baf9b59af` Send a plain it2 session set-var value as a JSON string | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `87d83b8f2` Show a restored session status in the tab bar | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `bf8b833e5` Keep hand-written triggers across a profile reload | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `4ccf2bc25` Accept an empty settings.json when uninstalling Claude Code hooks | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `bc248c3ab` Give settings.json the default mode when replacing a dangling symlink | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `f112110a5` Detect the shell reading the offline installer's commands | Skip removed shell installer/scripts; no submodules restored. |
| `1003663fd` Don't read a partial line as the zsh dotfile directory | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `6f7254113` Keep a local-model chat on Ollama when its model disappears | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `2121dddb9` Keep Cmd on an alert's shortcuts when it is shown again | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `1a10eb1e3` Keep Cmd-H, Cmd-Q, Cmd-W, and Cmd-M out of alerts' automatic shortcuts | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `074d280c8` Keep keyboard focus in a window after changing its style | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `cfa49e72c` Don't copy Lock Location to a duplicated window | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `4c9e292fa` Update pane title bars for sessions exchanged by Swap With Session | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `7f9f24a1c` Don't move a hotkey window to a tmux window's saved position | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `8d5538e58` Show the default in a string popup whose saved value isn't in its menu | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `013795e69` Remove two advanced settings that nothing reads | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `c663b0244` Disable Prefer integrated GPU on a Mac without both kinds of GPU | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `00ff77e7e` Clamp SetWindowFrame to the title bar's minimum width | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `2f8072822` Focus the number-of-spaces field in the paste-with-tabs prompt | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `01094a56e` Let Cmd-W close the Cockpit | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `e29a787c3` Count Advanced Paste preview lines correctly | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `253c19a32` Keep Remember unticked when the basic-auth prompt returns | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `bfc4d0ec7` Return JSON null for built-in functions that return NSNull | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `f1cd67a6b` Leave a tab alone when the API sets an unchanged layout | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `8a1cd9060` Fail -compare-rendering when another instance holds the lock | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `146d738d0` Keep -suite when LetsMove relaunches the app | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `46d513d7a` Drop the doubled period from the ssh sessions ended banner | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `8acabebb9` Count each arrangement session's command once in the trust gate | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `1314b06b3` Stop swallowing keys while an announcement slides away | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `85b51d9c4` Tint the workgroup git arrows for the toolbar's appearance | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `e4a99fc85` Don't animate status bar sparklines in Low Power Mode | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `83107911e` Forget cached password manager account names when auth is revoked | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `1a39452b8` Keep a failed pairing's error when AI is toggled | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `c0b68a52c` Restore the find field's caret when focus follows the mouse back | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `0f2ac83f3` Use the Internet-free installer when the website rejects nushell | Skip removed shell installer/scripts; no submodules restored. |
| `4ccbbe5db` Localize the AI tool-call bubbles and the Toggle Setting picker | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `23c4985b8` Translate Show Toolbar and Bell sound, and match pt-BR profile tags | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `8a5826243` Grow the crash reporter's explanation to fit its translation | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `ad5b0c58f` Keep the donation link from truncating the window title | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `05a520cdb` Fit Advanced Paste's translated labels | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `4fa93c7d4` Fit the Smart Selection sheet's translated labels | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `e71d57f02` Widen popup date columns to fit translated relative dates | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `90a364086` Widen the Profiles window's New Tab button for its translation | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `57c8730dc` Tell Badge and Icon apart in Russian | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `941edbeb8` Size the website permissions columns for their translations | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `c21efdd4b` Size the AI chat find bar's mode popup to fit its titles | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `e2d4c8243` Make room for translations in the manual AI model editor | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `033bb3a0f` Widen the AI model editor's API key popup to show its choice | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `8b6706f00` Keep the Hotkey settings labels clear of their controls | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `ce9e53572` Send Fetch Models through the AI proxy | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `b1b4a0897` Keep the AI chat find bar's search field usable when narrow | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `ecc07d674` Return focus to the chat input when the chat find bar closes | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `bb83d5e15` Let the user stop a running AI Test Connection | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `afd3607ff` Fix the wording of AI network errors | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `11ee1f1f6` Validate custom headers before an AI Test Connection | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `127a4f3d6` Escape control characters in claude_usage.sh's JSON | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `2bda0bd05` Refresh the chat's permission buttons after an info menu change | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `efeee3af9` Escape the session name in the orchestration grant notice | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `c7b26ed07` Stop logging every failed AI plugin validation | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `eaa8dc072` Don't double the typed directory when expanding {{FILE}} | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `696a31946` Treat Azure's sovereign and serverless AI hosts as Azure AI services | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `3aa834f1a` Drop alternate-screen bidi tables when reordering is turned off | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `8be414290` Anchor the Look Up highlight where an RTL word is drawn | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `29a335e89` Start legacy underlines at the leftmost drawn cell of an RTL run | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `013a840c8` Keep pre-base vowel signs before their consonant in the legacy renderer | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `dd4a86087` Draw the copy mode cursor where its character is drawn | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `335f1900f` Keep emoji ZWJ sequences and Base64 pastes intact when stripping | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `e33fa985a` Keep a running program's scroll region when restoring its session | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `275580c95` Grow the Internet-Free installer's step list to fit its text | Skip removed shell installer/scripts; no submodules restored. |
| `27a7ea1fb` Keep a maximized float's earlier frame on Undo Close | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `565d5f52b` Keep focus on a float docked by Control-drag | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `f74767055` Don't highlight a pane under a float as a swap target | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `ca1603f8a` Ask tmux to resize a tmux float instead of resizing it locally | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `ecb8e27fd` Give floats restored from an arrangement the arrangement's name | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `e083cab0a` Don't count hidden floats toward the GPU renderer's pane limit | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `9dc7d14af` Anchor tmux floats to the right pane while a filter is open | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `ace14a181` Don't let a dragged workgroup member become a float | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `fb30c1ede` Answer iTerm2-only reports in tmux integration panes | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `9ecd17ce1` Withdraw the it2 client record on Shell > tmux > Detach | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `996418e66` Stop double-escaping the composer's first file suggestion | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `5cbc7d7b1` Don't archive a tmux integration pane on closure | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `e62653351` Punctuate the Cockpit's skipped-target status and drop gone chips | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `7b82aa425` Don't treat a refused proxy icon drag as a click | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `2e23316c3` Put the cursor right after the session restored banner | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `2f8c65b46` Keep each pane's size when the API changes a tab's layout | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `935713b62` Keep Arabic joining at a selection edge in the legacy renderer | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `c78a9bf79` Decode JSON values in the remaining it2 commands | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `923838c76` Draw only the cropped part of a Kitty placeholder image | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `f3031cc39` Recognize it2ssh's EndSSH mid-frame in a restored session | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `459169fac` Resume AI chat watches at launch and let Stop cancel them without a dispatcher | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `66f8ce4ca` Keep an AI chat's pending timer armed when orchestration is enabled | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `f5d362a91` Keep a re-bound tmux watch's names while the reattached pane is unnamed | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `2b57a4547` Resize AI chat @-mention chips when the input's font changes | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `53b31bd41` Keep the AI Chats list selection on the chat that moves to the top | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `c2bcc5d11` Keep a chat on a removed manual model from going to OpenAI | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `278489547` Treat a csh parent as tcsh in offline installer discovery | Skip removed shell installer/scripts; no submodules restored. |
| `e8b2e91b6` Label the Profiles window’s New Floating Pane button | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `46cfe3ea7` Size the Set Profile Setting On/Off popup to fit its items | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `484622bfa` Shorten the German and Russian menu bar icon placeholders | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `6892690f1` Translate the browser error page’s button and footer | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `908e98a3b` Escape untrusted text on the browser error page | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `10985b169` Keep the find field's caret after changing the window style | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `372f593e2` Let Show menu bar icon change when Dock exclusion needs hotkey windows | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `464374ce7` Count each bad Dynamic Profiles file once in the error alert | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `1c9bb498f` Focus the pane under the pointer when a sheet closes | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `cead3c225` Substitute browser template placeholders in a single pass | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `aae5cce90` Add a regression test for Session Status rows following a job exit | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `5d678a9c8` Stamp a new chat's model vendor when the chat is created | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `bf655e047` Name settings.json, not its temp file, when a hook install write fails | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `b9fb908b1` Give the AI Chats window's chat pane a minimum width | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `225c6e2d7` Hide the AI-generated name title option for browser profiles | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `f57dd7e2b` Keep the Minimal theme's page tint from reaching the web view | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `f9fde08ab` Retire the global AI custom headers once models have their own | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `98c7ac71b` Keep the AI Usage report alert a manageable size | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `7e209fd8c` Fix crash when AI Chats search finds a match | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `16464ba7b` Use ps ucomm to find the shell for offline installer discovery | Skip removed shell installer/scripts; no submodules restored. |
| `3d339d8f7` Show the placeholder in the Toggle Setting and menu item pickers | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `995c9a245` Localize the units in Advanced Paste and Paste History sizes | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `8f4584024` Fit the installer's utilities checkbox and description to their text | Skip removed shell installer/scripts; no submodules restored. |
| `e75f3617e` Show the page source in the browser's View Source | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `14b02e228` Let a browser tab's page follow appearance changes | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `9f7aeaa2c` Fit the installer's buttons to their translated titles | Skip removed shell installer/scripts; no submodules restored. |
| `cb0b3e7c0` Let a session name from Edit Session out-rank an AI profile's fallback | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `98040bc3f` Open a popup browser tab's context menu in that tab | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `6b77dd670` Describe an unfinished AI tool call accurately in the next request | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `83a0a8dfd` Report a dead key's leftover character as the dead key in CSI u | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `ca0d0b9bb` Lay out the Minimal title again when only its subtitle changes | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `52a3e470a` Clear the unsaved-settings indicator after Save Now | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `ad9edb343` Show an error instead of crashing on a damaged script archive certificate | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `6f2d987b3` Restore a float's place in the z-order on Undo Close | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `8ef3bcc3c` Make each GPU-unavailable reason a complete sentence | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `21ebc658a` Pick the URL search pane with the logical coordinate | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `a39abb8b6` Stamp a command mark's start date once for both thread copies | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `a290e0cc1` Give the tab group context menu the window's appearance | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `71fb6def7` Decode HTML tab title entities even when there is no tag | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `c9b0cccd8` Dim the FFM subviews option on first show when FFM is off | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `47460b6e8` Size the Session Status priority popover to its translations | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `88c2b73eb` Make Find in Settings focus its search field | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `a6aa9855b` Shorten the German Undo timeout label in profile Session settings | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `cac078c4d` Translate “Type @” as a verb in the Chinese Cockpit hints | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `72c4fa851` Stop counting the next prompt in Command Info's output size | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `48d605f8d` Report -compare-rendering image save failures as errors | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `dc65dae7f` Keep Session.preferred_size in step with layout changes in the Python API | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `172b87ee6` Render a streamed reply's final code block as code | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `4b42791e0` Return xonsh to its prompt after the Internet-Free install | Skip removed shell installer/scripts; no submodules restored. |
| `25dea523e` Show a globe on mention chips for browser sessions | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `b3d54ae37` 3.7.6 release notes | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `f9f277f93` Drop Tahoe tab bar insets when using Sequoia-style tabs. Issue 12498. | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `6fbff128e` Remove blank lines added to the end of the 3.7 release notes | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `29ba8ff87` Keep the Internet-Free utilities install from hanging at a “> ” prompt | Skip removed shell installer/scripts; no submodules restored. |
| `b0e60d1a4` Recover SSH Integration sessions on Disconnect after it2ssh is killed | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `8e98b39bb` Focus the status bar search field under focus follows mouse | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `5cf47da63` Detect a killed it2ssh and recover the SSH Integration session | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `4ba711bb7` Hang up the ssh client a killed it2ssh leaves behind | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `732cfe0de` Kill rather than hang up the orphaned ssh client | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `a1adaf6e3` Ignore an abandoned SSH connection's framer output instead of recovering | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `2fadddaf2` Type every line of the Internet-Free install's bash dotfile step | Skip removed shell installer/scripts; no submodules restored. |
| `667e28e8c` Don't type an installer command after Cancel | Skip removed shell installer/scripts; no submodules restored. |
| `4a1356ee2` Never recover or hook from an abandoned SSH connection's queued output | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `1377d08c7` Check that the Internet-Free utilities install unpacked | Skip removed shell installer/scripts; no submodules restored. |
| `36888dfa6` Don't type the utilities archive into sh when it can't be received | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `5e3615b16` Stop typing the utilities archive when the installer is canceled | Skip removed shell installer/scripts; no submodules restored. |
| `34c9b9987` Retain the table of slowly sent pastes | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `3dad320d8` Restore the tty modes ssh changed when recovering from a killed it2ssh | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `2a2005bdc` Keep repairing tty modes until zsh records good ones | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `e0f6f020d` Return to the user's shell after canceling an Internet-Free install step | Skip removed shell installer/scripts; no submodules restored. |
| `04a6e81c6` Expect the v2 installer URL in the online installer tests | Skip removed shell installer/scripts; no submodules restored. |
| `82344fba2` Cancel an scp password request when the password manager closes | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `5c3a2150d` Don't overwrite a remote file when an upload's name check fails | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `42333afb4` Honor the generative AI lockout for Apple Intelligence | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `c788da7f3` Ignore malformed trigger parameters from untrusted dictionaries | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `77b3dde14` Read a signing certificate's expiration from its Not After date | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `9c5dbafc8` Don't unpack the utilities elsewhere when cd to ~/.iterm2 fails | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `4d907f27d` Percent-encode + in a URL template's query value | Ported in `046e68195`; see Partial Upstream Master Triage After 3.7.6. |
| `c9d1a3278` Draw the shell integration installer's Learn more links in the label font | Skip removed shell installer/scripts; no submodules restored. |
| `390aed4ed` Escape the composer's ghost text for file completions | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `90240d2c6` Highlight attribute values in View Source | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `f16ae5d8f` Point localization tests at the tracked string catalog | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `a0859af29` Exit installer helpers that start after Cancel, and detect leftover ones | Skip removed shell installer/scripts; no submodules restored. |
| `61f9d8b20` Keep drawing the shell's output after abandoning a streaming SSH connection | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `475f1e2b8` Don't type an abandoned SSH connection's commands into the local shell | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `b0ce81d15` Extract and translate the strings added in the QA fix pass | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `911c38938` Fold cc-status into it2 handle-agent-hook and resolve Claude Code's config directory | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `814de935d` Run it2 over SSH Integration | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `32e6234f4` Install the Claude Code integration on hosts reached through SSH Integration | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `b70785ffe` Bring jobs, git status, it2 and workgroup peers to hosts reached through SSH Integration | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `635cda4ed` Workgroups in tmux Integration | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `ea7819a7f` Add a framer test suite, fix framer bugs, and add framer flow control | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `231fd4d9d` Pace output from hosts reached through SSH Integration | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `39c9f5989` Fix tmux workgroups, remote git state and grants; load shell integration inside tmux | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `ad80b196b` Pace nested SSH Integration connections and add a flow control monitor | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `62f916dd7` Keep App Nap off while an iTerm2 Buddy phone is paired | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `5f1eadb63` Remove the LIVE badge from the iTerm2 Buddy session view | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `2959777d4` Keep the outer SSH connection going after disconnecting a nested one | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `156992306` Don't type framer commands into the new shells of restored SSH sessions | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `89775dd2e` Recognize a late unhook by its hook, not just its depth | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `22fadab31` Don't reset a framer that didn't survive a restart | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `c3477e8ff` Finish SSH Integration downloads in the Downloads menu | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `db8daf71b` Don't end a tmux connection selecting a window tmux already closed | Skipped in the latest triage: upstream renames a selector used by fork tests; any adaptation needs a focused follow-up. |
| `522847437` Keep focus in a tmux workgroup's slot when switching peers | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `c450cf1c5` Keep a tmux workgroup's peer in view when detaching | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `d0c4c39b6` Apply user variables a new tmux workgroup peer sets before its session exists | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `87e3ae336` Bury a filtered tmux workgroup member when a peer switch parks it | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `e90afae1a` Leave parked tmux workgroup windows out of the tmux Dashboard | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `9da747c45` Save window restoration state when a tmux gateway attaches | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `951bb2f5c` Keep Toolbelt Jobs following its session's root pid and process provider | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `479dbc2c4` Leave a tmux workgroup's peers in view to tmux when it ends | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `dd2ef1a38` Adopt a tmux workgroup when its leader's window opens later | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `2c8bee4ea` Don't crash making a tab active after it left its window | Ported in `046e68195`; see Partial Upstream Master Triage After 3.7.6. |
| `8144be2b4` Ask before closing a member of a tmux workgroup | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `08bc2bec9` Test that closing a tmux workgroup member leaves its peers to tmux | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `06ceda8db` Refuse workgroups in tmux Integration with tmux older than 3.2 | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `d3b985c6b` Keep the leader's window when exiting a workgroup whose peer was shown | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `d2ac604be` Count a filtered workgroup peer in view as in its tab | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `0ab0b9be1` Ask before closing a filtered tmux workgroup member | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `11fdf081a` Ask again where a tmux workgroup's leader is before ending it | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `bc26e447e` Forget the current tmux window when selecting it failed | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `243d5f281` Keep a tmux workgroup peer created this attach when detaching | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `963670d99` Kill a filtered tmux pane when closing it | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `240381b91` Drop the workgroup toolbar from tmux workgroup members that stay | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `5b59eb32a` Don't send tmux commands to a shell after restoring a detached gateway | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `5e01d4fae` Show a local tmux server's pane processes in Toolbelt Jobs | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `555ef2efb` Keep ~/.iterm2/bin first on PATH after a login zsh's startup files | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `e4f7df4d9` Turning off host control from the menu revokes the host's grant everywhere | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `ea561184e` Put ~/.iterm2/bin on PATH for a login shell that gets it2 without shell integration | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `a2089a0b9` Put it2 on PATH for a shell named as the it2ssh command | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `7e8db7cd7` it2ssh: exit 1 after usage, and refuse a misplaced --no-shell-integration | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `936a28bb2` Don't let a remote it2 in an unplaced tmux pane act on a tmux gateway | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `7374bd37a` Align and localize the API access over ssh button and its sheet | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `d1a58fed0` it2ssh: refuse --no-shell-integration wherever ssh reads options after the host | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `fa179d0ba` Exec a shell named as the it2ssh command instead of running it under the login shell | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `c9e1ae77e` framer: take IT2_PUT_BIN_ON_PATH out of its own environment | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `8cc3a2378` Give a remote workgroup peer the PATH of the user's interactive shell | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `373df1dfe` framer: remove a connection's /tmp it2 socket directory when it ends | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `b94c2d493` Stop calling the Claude Code hook cc-status in user-visible text | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `b3052589d` Accept a blank remote Claude Code settings.json and skip this Mac on uninstall | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `ce9199f6b` Don't edit a remote host's Claude Code settings when it might be this Mac | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `a275a69b6` Show the Claude Code uninstall confirmation promptly | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `ec4558b23` Don't judge a connection back to this Mac as having a remote Claude Code hook | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `e9511cd18` Remove tty mode repair after a killed it2ssh | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `832066203` Remove killing of orphaned ssh clients | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `281cea805` Remove automatic detection of a killed it2ssh | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `270ca41c4` Let Disconnect end an SSH connection before its framer starts | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `1e67f5c03` Rebuild the it2 binary | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `87d437410` Don't hang the Internet-Free install where sh is dash | Skip removed shell installer/scripts; no submodules restored. |
| `7fa94b141` Send the shell integration script to the helper sh in short lines | Skip removed shell installer/scripts; no submodules restored. |
| `9a11cff3b` Start the Internet-Free install's helper sh with one line | Skip removed shell installer/scripts; no submodules restored. |
| `03eebdc7f` Erase the user's typing before exiting the installer's helper sh | Skip removed shell installer/scripts; no submodules restored. |
| `937ce398c` Fit a filter's stand-in to its view in tmux tabs | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `c151bb32d` Refit filter stand-ins in tmux tabs when their views change | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `b58fab8cf` Keep a tmux workgroup's leader in place when detaching | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `d22f0c651` Name the filtered session in its close confirmation | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `908eb6b51` Don't save window restoration state on tmux attach or detach | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `b7f28af96` Name a remote session's job after the foreground job on its terminal | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `a18224fc9` Don't inject macOS's bash named as the it2ssh command under another login shell | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `5da164a2b` Put ~/.iterm2/bin on PATH once for a shell named as the it2ssh command | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `e9786b8bd` Refuse an it2 prompt for a tmux pane this connection doesn't show instead of waiting forever | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `eb2f4eec4` Answer the EndSSH of an it2ssh whose connection aborted | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `2f4270d3d` Treat nu named as the it2ssh command as a shell, so it gets shell integration | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `d76040188` Honor Stop Allowing during uninstall even when the hook stays | Skip removed shell installer/scripts; no submodules restored. |
| `eb3f4cf90` Give up on an unresponsive host quickly during uninstall and say so | Skip removed shell installer/scripts; no submodules restored. |
| `13f1b6cd9` Say what the tmux pane lookups' origin scoping actually guarantees | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `bb60d7218` Let Download Files choose any file (F-895) | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `00f4bebec` Say why a connection is unpaced as decided when it started | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `69d0b490a` Keep the flow control monitor on across a restart | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `3452fc03b` Don't claim flow control was never tried on a stopped connection | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `33187b479` Let Cmd-W close the flow control monitor | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `7a1367f54` Redraw the flow control monitor only when it changes or once a second | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `5c7113da4` Notice new flow control events once the monitor's list is full | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `8057b11b6` Update shell integration: it2ssh option checks, it2 tmux lookup, PATH order, nushell | Skip removed shell installer/scripts; no submodules restored. |
| `d52b2b98b` Keep macOS metadata out of the utilities archive | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `e7bc90fa2` it2: route by tmux session id on both sides | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `cc6280f26` Rebuild the it2 binary | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `33fb90776` Bury a filtered tmux peer when a switch brings pane %0 into its slot | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `e6e13ee0b` Accept non-ASCII it2ssh arguments and never leave the remote waiting | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `6fc99cb40` Translate the unreadable it2ssh arguments banner | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `6b9d7f936` Test ending a nested it2ssh whose arguments can't be read | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `289681483` Keep a finished program's output out from under the restart offer | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `ed628f051` Fix crash finishing an SSH Integration download on a user@host connection | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `7d735855c` Don't nest a folder downloaded over SSH Integration inside itself | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `a358ffeed` Report a failed context-menu download instead of doing nothing | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `2966873f3` Add a release note for the user@host parsing fix | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `e0f077e36` Don't type the pre-framer quit into a shell on Disconnect | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `4a4bd021a` Send tmux integration's opening ^C through the SSH Integration framer | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `23090b7cd` Don't recover a restored SSH connection whose ssh ended | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `caabf13d0` Frame keys typed in a connection nested in one without a framer | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `e3639138b` Send nothing but the quit after an SSH connection's login shell exits | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `6aba6a57c` Explain why tmux integration can't start inside a tmux integration session | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `81d66a923` Log an unpauser released while still paused only when that happens | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `21bc38e28` Answer an it2ssh EndSSH no connection started with a bare ^C | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `44f5b04e0` Bump shell integration: it2ssh stops on a bare ^C and returns ssh's status | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `33a498421` Start an injected remote bash as a login shell | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `be774fda6` Name the file in failed transfer notifications | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `610a5b4ad` Treat a canceled file transfer as canceled, not failed | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `207954462` Localize SSH Integration file transfer failure reasons | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `3610cd1f7` Say when an SSH Integration transfer fails for lack of permission | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `bcca9c116` Localize the Downloads and Uploads menu titles and sizes | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `a705ad7ac` Discard a declined terminal-initiated file instead of drawing it | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `80b80f8d9` Give a folder download's archive permission error the generic reason | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `16cc692c8` Give the Uploads menu a Russian title distinct from Downloads | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `f637cb8e9` Say when a folder download over SSH Integration left out files | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `9c164c4b9` Use the Russian word for sending in upload strings | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `0f330a091` Keep a long download status from running into its size | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `54a65ad1c` Remove the hidden temp file when an SSH Integration download fails | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `b1df11bf0` Download over SSH Integration with pipelined 4 KiB requests | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `e076d23f5` Fail an SSH Integration download that can't be moved into place | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `dd4d18f3b` End a failed SSH Integration download in the failed state | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `a4b7bb558` Translate the SSH Integration download move-failure reason | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `eb5ef8e4b` Clean up right away when a stalled SSH Integration download is stopped | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `171e435ff` Put a floor of 15 under the screen's refresh rate for Metal views | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `4702a68cf` Put the F-920, F-921 and F-960 download code where F-724 moved it | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `ea63211c8` Expect a bare ^C for an EndSSH no connection started in the abort test | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `2190c6531` Don't recover an adopted orphan job's SSH connection whose ssh ended | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `8ea34d102` Add 3.7.7beta2 release notes | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `c017ccbb3` Bump shell integration script versions | Skip removed shell installer/scripts; no submodules restored. |
| `c61405623` Make a held Delete key repeat when typing into a session in iTerm2 Buddy | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `8634ad695` Bump companion version to 1.5 | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `12c882686` Opt out of AppKit window and tab title indexing | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `540eb597b` Bump PushService extension version to 1.5 | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `df72ea406` Skip call stack logging when reloading dynamic profiles. Issue 13174. | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `8f916227d` Bump companion MARKETING_VERSION to 1.5 in the project generator | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `9f2aba29a` Run sheet warning completions after the sheet has ended | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `6d9acd06d` Keep Claude Code hooks from piling up behind an unanswered consent prompt. Issue 13175. | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `0ab4c83f7` Keep a session's profile type fixed when its shared profile changes type | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `71309eb6b` Keep right prompts out of command history and fix stale autocomplete prefix. Issue 13168. | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `afce7c434` Offer the Claude Code integration only for interactive claude sessions | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `82863e040` Make TaskNotifier testable and add characterization tests | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `920ea43ab` Fix task I/O bugs ahead of the TaskNotifier migration | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `5ae976802` Add ChildReaper behind the useTaskIOMonitors gate | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `9a37dd4b9` Replace TokenExecutor's semaphore with TokenBudget | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `88bfef39b` Add TaskIOMonitor behind the useTaskIOMonitors gate | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `bb4085588` Give task file descriptors an owner that monitors lease | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `fca9e88e0` Replace the SIGCHLD handler with logging when task I/O monitors are on | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `24cc4d35e` Restart sessions only after the old task's monitor stops | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `76018ad84` Read tmux pane output from memory, with gateway backpressure, when task I/O monitors are on | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `443eb2acb` Give owned file descriptors pipe and flag helpers, and use them in place of fcntl | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `4e1538b96` Log task I/O monitor lifecycle events and stalls | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `7284fa231` Track mutation queue join state per queue instead of per process | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `c5025042f` Make process-wide caches and counters safe to use from several mutation queues | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `41a5456f1` Pause only the joined session when it has a mutation queue of its own | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `9110182f3` Restore the main-thread state after joins in screen tests, and assert it | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `a8b4dbae7` Always join in performBlockWithJoinedThreadsReentrantSafe: | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `c13e63757` Fix more state that is unsafe once sessions have mutation queues of their own | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `31b57eb23` Give each session a mutation queue of its own when task I/O monitors are on | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `e17554735` Don't wait for a busy session to go idle before joining it when it has its own queue | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `87b550822` Add the issue 13141 keystroke latency harness | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `a527419d8` Wait for queued tokens to execute in screen tests instead of relying on an empty join | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `43505d9d6` Keep tmux from queuing a backlog when the gateway pauses reading | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `2b304d4a4` Turn on task I/O monitors and per-session mutation queues in beta builds | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `a58eef598` Add a tmux control-mode backlog repro and record threads and memory in the 13141 harness | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `574e1ab87` Limit how many sessions execute tokens at once | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `1fb625788` Keep execution permits off the lock when sessions aren't competing | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `565f5ded5` Report bytes executed per second in the token execution stats | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `4739bd78e` Send executor updates to the main thread from one shared ticker | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `0c99c5735` Recover from lost execution permit wakeups | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `bef13b6d2` Put execution permit state in debug logs | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `49fe45f9d` Add an advanced setting to turn off the limit on sessions processing output | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `f71dee304` Time each keystroke's echo in the token execution stats | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `c6f30976c` Add a workload script for measuring output throughput and its CPU cost | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `7ac57533c` Don't make a UUID for every line block | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `09bf12d97` Add a script that generates different kinds of terminal output | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `2e46a53be` Check the execution permit time slice every 8 tokens instead of every token | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `49ac84a91` Load the terminal's weak delegate once per token | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `a3791116a` Hash and compare complex character strings outside the registry's lock | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `8dc03200e` Wait for character width tables to finish initializing before reading them | Ported in `046e68195`; see Partial Upstream Master Triage After 3.7.6. |
| `9b3abc01d` Keep the workgroup list behind a lock so triggers can read it off the main thread | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `5d2a98725` Read advanced settings without racing a change on another thread | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `c09ee59ff` Point the shell integration submodule back at 0296291 | Skip removed shell installer/scripts; no submodules restored. |
| `96d438b7b` Read the Claude session's terminal mode through the task's owned descriptor | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `975dc36f2` Expect the process group column in the framer's ps command | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `f5673fce8` Read a tmux pane's tty with if-shell instead of run-shell | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `c1d998db3` Log a Metal view's colorspace only when it changes | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `dd762882f` Make concurrency tests able to see the bugs they guard against | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `ab7eb9715` Test that a join of one session leaves another executing | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `880d59f0e` Share the task read capacity decision between PTYSession and the tests | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `657c21534` Test registering a task without a usable descriptor, and a redundant registration | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `ddb3a575c` Test that coprocess EOF terminates the coprocess before reaping it | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `f9afd8f79` Test the ticker's real timer source and expedites racing marks | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `9838f3f37` Test that a session freed while waiting for or holding a permit gives it up | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `269f72560` Say what was still pending when screen tests give up waiting for tokens | Skip removed product surfaces; review any shared terminal prerequisite separately if a retained feature needs it. |
| `1d9c74927` Keep terminal windows resizable when the layout engine is engaged | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `a2126c9b2` Credit the x-man-page report in release notes. Issue 13156. | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `50dda4f98` Show a restored arrangement's window only after its frame is applied | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `2d48c2706` Don't stack another scrim each time Show is clicked in the Show Toolbelt onboarding step (#800) | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `7ea65c742` Confirm before Close Other Tabs and Close Tabs to the Right close tabs with running jobs. Issue 13185 | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `681b44add` Request only the vm_statistics64 revision the memory component reads | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `8ab929ea5` Skip per-cell drawing timers unless drawing performance logging is on | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `dcd01a915` Fill the window when unmaximizing a pane after a window resize | Deferred: depends on the floating-pane setNativeRootFrameSize: refactor absent from the fork. |
| `e736e12b1` Remove a leftover conflict marker from the release notes | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `dbceb3cd7` Lift the ban on Auto Layout in terminal windows | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `f49137e8a` Report mouse motion when an app enables it with CSI ? 1003 h. Issue 13184 | Ported additionally: joined main-state mouse tracking; regression tests recorded above. |
| `eac988157` Replace the computed box-drawing lower bound with a constant | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `eaee1c8f4` Drop stale and redrawn right-prompt exclusions | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `731e0e23c` Mark the zsh right prompt for iTerm2 | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `c18299754` Mark the fish right prompt for iTerm2 | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `8febee7d4` Mark the tcsh right prompt for iTerm2 | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `c936f0bae` Skip flaky TriggerInterpolatedParameterTests.testResultIsCached | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `4c0df9c3a` Read the process table with one sysctl per process cache refresh. Issue 13182. | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `715a7d266` Log session, tab, window, and global variables in debug log header and footer | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `db940e958` Keep a tab drag locked to its tab bar until it moves well away. Issue 13151 | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `0f4a13f8d` Restore state after joins in every terminal test harness | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `8940ad725` Add Korean localization (#806) | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |
| `5ec7e29a9` Keep the stoplight buttons off the session with a right-side tab bar. Issue 13153. | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `5080209f8` Keep window size when the tab bar hides after a tab drag (#13165) | Defer post-3.7.6 master candidate: inspect/adapt in next stable maintenance batch with focused regressions; not part of v3.7.6 contents. |
| `095beb457` Fill in missing translations after extracting strings | Skip upstream distribution/localization/tooling replacement; retain fork workflow and translations. |

- Final Development build passed after relay fallback adaptation. Advanced Settings localization: 4 checks passed. Advanced conductor recovery test cast warning removed without changing behavior. UPSTREAM now names stable 7ce456b98db38d3f0bafd70ffec87752e69d5d58 after the complete stable classification and selected-fix verification. Version prepared as 26.11.1. Notarization preflight currently lacks Keychain profile latterm-notary; Developer ID certificate is valid, user asked to restore the profile while signed packaging proceeds.

- Release handoff: pushed clean through 721d933aa (26.11.1) after all source/dependency commits. Signed Deployment build passes, no compiler warnings in changed release files; 17 bundled Mach-O files support arm64 and macOS 12.4 (two existing helpers also carry x86_64). No developer-home dylib dependencies. Strict/deep Developer ID signature and hardened runtime verified; isolated -suite Latterm launch remained healthy. Signed pre-notarization ZIP: Build/ReleaseStaging/26.11.1/Latterm-26.11.1-prenotarized.zip. Draft GitHub release created, not published and no final assets uploaded. Apple notarization is blocked solely by missing local Keychain profile latterm-notary; user asked asynchronously to restore it or name an alternative. Resume details in ignored tmp/release-26.11.1-state.json; temporary finalize script /tmp/latterm-finalize-26.11.1.sh signs off notarization/stapling/extracted ZIP before uploading and publishing. Initial GitHub direct connection timed out; command-scoped proxy through existing KPLX 127.0.0.1:7890 made push succeed, without changing Git config.

- Unattended follow-up: user authorized autonomous verification/commit/push/release and requested system sleep at completion. Notary profile could not be recovered: no matching metadata in login or data-protection Keychain, explicit login lookup fails, known keychain temporary file is empty. No credentials exposed or interactive prompts requested. Extracted signed ZIP passes strict/deep verification; SHA-256 saved alongside pre-notarization ZIP. Release remains a draft until credentials are restored. Display sleep requested during final checks, then system sleep will be requested.
