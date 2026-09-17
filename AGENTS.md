# Latterm Agent Guide

> Essential guide for AI agents working on Latterm, the terminal-first iTerm2 fork.

## Critical Rules

**Read this guide before making changes**, including the mandatory Code Best Practices below. Key rules:

1. **Never** write >1 line of JavaScript/HTML/CSS inline - use external files with `iTermBrowserTemplateLoader.swift`
2. Use `it_fatalError` and `it_assert` (not standard `fatalError`/`assert`) for proper crash logs
3. **Never** create dependency cycles - use delegates/closures instead
4. `git add` new files immediately after creation
5. Read `REFACTOR.md` before any large feature-removal, modernization, or Swift-migration task. Treat it as the staged roadmap for the terminal-first fork and as a local planning document unless the user explicitly asks for it to be committed.
6. As features are removed, audit their git submodule dependencies and delete submodules that are no longer needed. The long-term target is zero submodules, but never remove one before all code/project/runtime references are gone.

## Upstream Review Cursor

The root `UPSTREAM` file contains one full commit hash from the official
`gnachman/iTerm2` repository. It is a reviewed-through cursor, not a claim that
Latterm contains every upstream commit and not necessarily a Git merge base.

When reviewing upstream changes:

1. Read the current hash before fetching or comparing anything.
2. Use an `upstream` remote pointing to `https://github.com/gnachman/iTerm2.git`.
3. Fetch with `git fetch --no-recurse-submodules upstream master --tags`. Never
   let an upstream review restore submodules already removed by this fork.
4. Review both `UPSTREAM..upstream/master` and the latest official stable/test
   release tags. Release tags may be cut from a release branch rather than be
   ancestors of `master`, so compare their contents instead of assuming a
   linear tag history.
5. Classify the whole range before changing the cursor:
   - Port terminal-core security, correctness, compatibility, and measured
     performance fixes that still apply.
   - Skip browser, AI/model, shell-integration, and other removed product
     surfaces rather than recreating their dependencies.
   - Adapt overlapping fixes manually when the fork has structurally diverged.
   - Record worthwhile deferred candidates in `REFACTOR.md` so advancing the
     cursor does not make them disappear from the roadmap.
6. Apply selected changes as focused patches, audit submodule implications,
   and run proportionate tests plus a Development build.
7. Update `UPSTREAM` to the full reviewed upstream commit only after the entire
   intervening range has been classified and all selected changes pass
   verification. If the review is incomplete, do not advance it.

## Architecture

**iTerm2** uses hybrid Objective-C/Swift: core system in Objective-C, modern features in Swift.

**Application Flow:** App → Window/Tab → Session → Terminal Emulation → Rendering

### Key Components

- **Application:** `iTermController` - Main coordinator
- **Window/Tab:** `PseudoTerminal`, `PTYTab` - Window and tab management
- **Session:** `PTYSession` - Session lifecycle, I/O, state
- **Terminal Emulation:** `VT100Parser`, `VT100Terminal`, `VT100ScreenMutableState`, `VT100Screen`, `VT100Grid`
- **Rendering:** `PTYTextView` - Metal-accelerated rendering

## Directory Structure

```
iTerm2/
├── sources/               # Main application code
├── tests/iTerm2XCTests/   # Unit tests
├── proto/api.proto        # Protocol Buffer API
├── tools/                 # Build scripts
├── submodules/            # Git submodules
├── iTerm2.sdef            # AppleScript API
├── AGENTS.md              # Agent guide and code best practices
├── REFACTOR.md            # Terminal-first fork roadmap
└── iTerm2.xcodeproj/      # Xcode project
```

## Common Development Tasks

### Modifying Terminal Emulation
- Escape sequences flow: `VT100Parser`/`VT100Terminal` → `VT100ScreenMutableState`/`VT100Screen` → `VT100Grid`
- Look at `ModernTests/VT100ScreenTests.swift` and `ModernTests/VT100GridTests.swift` for examples
- Test changes thoroughly

### Extending APIs
- **WebSocket API:** Edit `proto/api.proto`, run `tools/build_proto.sh`
- **AppleScript:** Edit `iTerm2.sdef`, implement in `*+Scripting.{h,m}` files

## Code Patterns

### Avoiding Dependency Cycles
```swift
// ❌ Bad: Strong reference cycle
class Parent { var child: Child? }
class Child { var parent: Parent? }

// ✅ Good: Use weak reference
class Child { weak var parent: Parent? }
```

### Using External Templates
```objc
// ✅ Good
NSString *html = [iTermBrowserTemplateLoader loadTemplateNamed:@"chat"];

// ❌ Bad: Inline HTML
NSString *html = @"<html><body>...</body></html>";
```

### Error Handling
```swift
// ✅ Good
it_fatalError("Unexpected state")
it_assert(value != nil, "Value required")

// ❌ Bad: Won't create crash logs
fatalError("Unexpected state")
assert(value != nil)
```

## Finding Your Way

**Language choice:**
- Use Objective-C when modifying existing Objective-C code
- Use Swift for new features
- Use `@objc` attributes for Swift/Objective-C interop
- The Swift bridging header is `sources/iTerm2SharedARC-Bridging-Header.h` - check here for available Objective-C types and constants in Swift

**Where code lives:**
- Session logic → `PTYSession.{h,m}`
- Terminal emulation → `VT100Parser`, `VT100Terminal`, `VT100ScreenMutableState`
- UI rendering → `PTYTextView.{h,m}`
- Tests → `tests/iTerm2XCTests/`

## Code Best Practices

- Avoid writing javascript, html, or CSS that's more than one line long in Swift. Create a new file and use the existing template mechanism to load it.
- After creating a new file, `git add` it immediately
- To add a file to the Xcode project, use `tools/add_file_to_xcodeproj.rb <file_path> <target_name>` (e.g., `tools/add_file_to_xcodeproj.rb sources/Example.swift iTerm2SharedARC`)
- The Companion app's Xcode project (`Companion/iTerm2Companion.xcodeproj`) is generated from scratch by `Companion/tools/generate_companion_project.rb`, which is the source of truth. That script does NOT use `add_file_to_xcodeproj.rb`. After adding, removing, or renaming a Companion source file, re-run the generator and commit its output. Crucially, any structural change made in Xcode (a new target, a Swift package dependency, entitlements, or a build setting) MUST be mirrored back into the generator in the same commit, because the next regeneration overwrites the project wholesale and would otherwise silently drop it. If the two drift, regenerating produces a broken build.
- In Swift, use it_fatalError and it_assert instead of fatalError and assert, which do not create useful crash logs. In ObjC, assert is ok although ITAssertWithMessage is preferable. Asserts are enabled in release builds.
- Don't write more than one line of inline javascript, html, or css. Instead create a new file and load it using iTermBrowserTemplateLoader.swift
- Don't create dependency cycles. Use delegates or closures instead.
- To run unit tests in ModernTests, use tools/run_tests.expect. It takes an argument naming the test or tests, such as `tools/run_tests.expect ModernTests/iTermScriptFunctionCallTest/testSignature`
- AI chat and model integrations have been removed from the terminal-first fork; do not add new AI live harnesses or vendor API test paths.
- When renaming a file tracked by git (and almost all of them are) use `git mv` instead of `mv`
- To make a debug build run `tools/build.sh` (or `tools/build.sh Development`). This saves logs to `tmp/build.log` and shows only errors/warnings on failure.
- Little scripts or text files that are used for manual testing of features go in tests/
- The deployment target for iTerm2 is macOS 12. You don't need to perform availability checks for older versions.
- Don't replace curly quotes with straight quotes. Same for apostrophes and single quotes. If you need help typing a curly quote, just ask. Here are some you can copy and paste: ‘’“”
- In user-visible strings do not use " except as a shorthand for inch. Prefer curly quotes like “ and ”. I know this goes against your nature, but fight hard here.
- Ask permission before using auto layout if it's not already in use in a given file. Debugging auto layout is the worst hell.
- The deployment target is macOS 12. Don't add availability checks for 12 and lower.
- Never `git add` submodules without express written permission.
- Don't include AI-generated markdown files (summaries, plans, etc.) in commits — only ship code.
- Avoid duplicate expressions; hoist shared computations into a named `const` before branching.
- Don't change defaults silently.
- Use [iTermUserDefaults userDefaults] instead of [NSUserDefaults standardUserDefaults]
- Use `make run` to build and run a debug build.
- Never run the app without the argument `-suite suitename` where `suitename` is the last path component of the current directory. To run a development build, just do `make run`. Omitting -suite causes conflicts between the new instance of iTerm2 and the main instance used for development.
- Do not use associated objects (objc_getAssociatedObject or objc_setAssociatedObject) without express written permission.
- You should treat warnings as errors.
- If you get stuck, ask for help. It's better to ask me to look at something in the debugger than to flail around for a long time.
- If your changes introduce compiler warnings, fix them.
- After landing a feature or bugfix, update docs/notes-3.7.txt (the release notes). Max width of a line is 50 characters.
- For changes to the Companion iOS app (the `Companion/` directory, "iTerm2 Buddy"), put release notes in Companion/docs/notes.txt instead of docs/notes-3.7.txt.
- The sources directory is organized into folders. Before adding a new file, consider which directory it belongs in. Some are named after features while others are named after their role.
- User Defaults keys that should only be stored locally begin with the prefix NoSync. If a user chooses to load prefs from a custom location (e.g., Dropbox) they may be prompted to write settings when a non-NoSync key changes. To avoid disrupting them in this manner, user defaults that are not actual configuration settings (e.g., a list of recent items) get a NoSync prefix.
- Use DLog statements so we can debug problems in the field. These statements have no effect when debug logging is off (the default) and it's OK for them to do somewhat expensive operations like getting a stack trace.
- Use RLog statements to log debug messages to memory even when debug logging is not on. Creating a debug log later will pull in the last 10 megabytes of RLog statements. RLog runs always so don't do anything expensive (such as stack traces) and do not use them in hot paths that could burn a lot of CPU logging.
- When adding temporary code for debugging, use NSFuckingLog instead of NSLog because NSLog truncates long output. Logging code that is intended to remain long-term should use DLog.
- Do not use an SF Symbols name as a string literal. Get it using SFSymbolGetString in Objective C or the SFSymbol enum in Swift.
- Don't use sleep to solve concurrency problems.
- Tests should not be flaky. Don't write tests that will fail if the system is slower than usual.
- DONE (companion NSE wire structs, syncSince): the syncSince leaf structs now live once in the package (CompanionSyncItem.swift, with `author` as a String to avoid hoisting Participant); CompanionHostMessage.syncSince and the NSE both use them, so NSESyncSince is just a thin envelope and the item-level cross-check is gone along with the `_0`-nesting footgun. The legacy messagesSince mirror (NSEMessagesSince) was deliberately NOT refactored: it is part of the revision-1 path the cleanup TODO below deletes wholesale, so sharing its structs would be wasted work.
- TODO (companion protocol cleanup): when 3.7 beta 6 or a stable 3.7 ships, remove support for the revision-1 companion protocol. That means dropping the legacy per-chat collapse-token push path entirely: delete `CompanionPushSender.sendMutable` and the legacy branch in `CompanionPushSender.dispatchPush`, the `messagesSince` client/host messages and `handleMessagesSince` in CompanionHostBridge, the `messagesSince` path in the NSE (NSEFetcher.fetch / NotificationService.runLegacy / the sentinel-vs-token branch in didReceive, since every push will then be a wakeup), `NSEMessagesSince` and `PushFetchCoordinator` and their tests, and raise `CompanionProtocolVersion.minimumPeer` to 2 so revision-1 peers are told to upgrade. Keep only the contentless wakeup + `syncSince` path. At that point the HMAC per-chat key is no longer exposed off-device, so also simplify the watermark/thread keying to the raw chatID and drop `CompanionThreadKey` / `CompanionCollapseToken` from this path (a coordinated change with `CompanionClient.advancePushWatermark`).
