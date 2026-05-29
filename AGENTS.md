# iTerm2 Agent Guide

> Essential guide for AI agents working on iTerm2.

## Critical Rules

**Read `CLAUDE.md` first** - it contains mandatory coding practices. Key rules:

1. **Never** write >1 line of JavaScript/HTML/CSS inline - use external files with `iTermBrowserTemplateLoader.swift`
2. Use `it_fatalError` and `it_assert` (not standard `fatalError`/`assert`) for proper crash logs
3. **Never** create dependency cycles - use delegates/closures instead
4. `git add` new files immediately after creation
5. Read `REFACTOR.md` before any large feature-removal, modernization, or Swift-migration task. Treat it as the staged roadmap for the terminal-first fork and as a local planning document unless the user explicitly asks for it to be committed.
6. As features are removed, audit their git submodule dependencies and delete submodules that are no longer needed. The long-term target is zero submodules, but never remove one before all code/project/runtime references are gone.

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
├── CLAUDE.md              # Code best practices
├── REFACTOR.md            # Terminal-first fork roadmap
└── iTerm2.xcodeproj/      # Xcode project
```

## Common Development Tasks

### Modifying Terminal Emulation
- Escape sequences flow: `VT100Parser`/`VT100Terminal` → `VT100ScreenMutableState`/`VT100Screen` → `VT100Grid`
- Look at `VT100ScreenTest.m` for examples
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
