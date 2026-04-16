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

### Recent Verification

- `xcodebuild -quiet -project iTerm2.xcodeproj -scheme iTerm2 -configuration Development -destination 'platform=macOS' -skipPackagePluginValidation CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO ARCHS='arm64' ONLY_ACTIVE_ARCH=YES -derivedDataPath /tmp/iTerm2-derived-phase2 build` passes on 2026-04-15 after the phase2 browser-session cleanup.
- `xcodebuild -quiet -project iTerm2.xcodeproj -scheme iTerm2 -configuration Development -destination 'platform=macOS' -skipPackagePluginValidation CODE_SIGN_IDENTITY='' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO ARCHS='arm64' ONLY_ACTIVE_ARCH=YES -derivedDataPath /tmp/iTerm2-derived-phase3 build` passes on 2026-04-16 after the phase3 AI-removal build-recovery cleanup.

## Refactor Direction

The target product is a terminal-first app:

- Terminal emulator, sessions, tabs, panes, rendering, profiles, and basic preferences stay.
- Browser sessions are removed.
- AI chat, AI agents, and model integrations are removed.
- Shell integration, its installers, and shell-integration-only UX are removed.
- Old compatibility constraints should be relaxed so the surviving code can use a more modern macOS baseline and Swift-first patterns.

## Current Repository Observations

The removal scope is real, not hypothetical:

- `sources/Browser/**` contains roughly 197 files.
- AI/chat-related sources account for roughly 34 files under `sources/`, plus the separate `iTermAI/` project.
- Shell integration and closely related sources/resources account for roughly 33 files.
- `sources/PTYSession.m` is a major coupling point across terminal, browser, scripting, shell integration, triggers, and UI.
- The source tree is still heavily Objective-C weighted: about 567 Swift files vs about 1711 Objective-C headers/implementations in `sources/`.
- There are multiple optional-feature submodules. The clearest early removal candidate is `submodules/iTerm2-shell-integration`, but it should only be deleted after all compile-time and runtime references are gone.

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
- `sources/AITerm*`
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

- Do not start phase 3 by deleting the chat stack. `ChatWindowController`, `ChatClient`, `ChatBroker`, `ChatService`, `ChatAgent`, and `ChatDatabase` are tightly coupled and should be treated as a later slice.
- The safest first phase 3 cut is the Claude Code watcher/onboarding pair: `sources/ClaudeWatcher.swift`, `sources/ClaudeCodeOnboarding.swift`, and the two app-delegate hooks that start/show them.
- AI completion is a reasonable second slice, but it must include both `sources/AICompletion.swift` and the `CompletionItem.Kind.aiSuggestion` handling in `sources/CompletionsWindow.swift`.
- `sources/ToolCodecierge.swift` is not leaf-clean. If removed, do it together with its toolbelt registration and any AI-specific help/tip text.
- The shared AI gate/client layer (`sources/AIPluginClient.swift`, `sources/iTermAITermGatekeeper.swift`) is broad enough that it should follow the UI/onboarding cleanup, not lead it.

### Shell Integration

Primary removal candidates:

- `Resources/shell_integration/**`
- `sources/ShellIntegrationInjection.swift`
- `sources/Bundle+ShellIntegration.swift`
- `sources/iTermShellIntegration*`
- `sources/iTermShellPromptTrigger.*`
- `sources/iTermShellHistoryController.*`

Likely follow-on cleanup:

- Shell-integration-specific notices and version checks in `PTYSession`
- Trigger descriptions and warnings that depend on shell integration
- Profile or preferences UI that installs, updates, or advertises shell integration

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

- `submodules/iTerm2-shell-integration` once shell integration code, resources, and installer flows are gone
- `submodules/adblock-rust` once browser support is gone
- `submodules/SwiftyMarkdown` once AI/chat and markdown-only surfaces are gone, if no surviving UI still depends on it

High-risk later targets:

- `submodules/NMSSH`, `submodules/libssh2`, `submodules/openssl`
- `submodules/libsixel`
- `submodules/libgit2`
- `submodules/fmdb`
- `submodules/BTree`
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

1. Remove the Claude Code watcher/onboarding startup and menu hooks, then delete `sources/ClaudeWatcher.swift` and `sources/ClaudeCodeOnboarding.swift`.
2. Remove terminal AI completion (`sources/AICompletion.swift`) together with the `.aiSuggestion` UI branch in `sources/CompletionsWindow.swift`.
3. Remove Codecierge AI surfaces only after deleting its toolbelt registration and related tip/help text.
4. Tackle the shared AI gate/client layer and the chat stack only after the surface/onboarding slices above are gone.

Success criteria:

- No UI path, target, or preference remains for AI features.

### Phase 4: Remove Shell Integration

Goal: stop patching the shell environment and prune dependent UX.

- Remove shell integration injection from session startup.
- Delete installers, panels, resources, and update prompts.
- Remove shell-integration-specific triggers, warnings, and helper controllers when their value disappears without shell integration.
- Re-evaluate semantic history and command history features: keep only what still makes sense without shell-side hooks.

Success criteria:

- Launching a session no longer injects shell integration and the app has no shell-integration install/update UX.
- `submodules/iTerm2-shell-integration` is removed once no project, resource, or runtime references remain.

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
- Update documentation and packaging.
- Remove leftover iTerm2 branding that is no longer accurate for the fork.

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
