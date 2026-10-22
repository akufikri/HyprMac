# HyperMac — Technical Reference Document

## 0. What HyperMac is not

HyperMac is **not a compositor and not a Desktop Environment**. It does not own a display server, does
not implement Wayland protocols, does not composite surfaces, and never renders window content. The
macOS WindowServer remains the compositor; HyperMac is one more Accessibility (AX) client that reads
and writes other apps' window frames. Every architectural decision below follows from that: there is
no frame callback, no damage region, no buffer, and no way to draw anything except its own menu-bar UI.

```
┌──────────────────────────┐        ┌───────────────────────────────┐
│ HyperMacApp (SwiftUI)    │        │ hypermac (CLI executable)     │
│ @main, MenuBarExtra,     │        │ parses args → ClientRequest    │
│ calls initAppBundle()    │        │ → unix socket → ClientRequest  │
└───────────┬──────────────┘        └───────────────┬───────────────┘
            │ links                                │
            ▼                                      ▼
┌────────────────────────────────────┐   /tmp/dev.hypermac.HyperMac-<user>.sock
│ AppBundle  (the engine)            │◄──────────────────────────────────┘
│  initAppBundle → config → AX check │
│  GlobalObserver (AX notifications) │   JSON  ClientRequest  {args, stdin}
│  tree: Workspace → TilingContainer │   JSON  ServerAnswer   {exitCode, stdout, stderr, version}
│        → Window                    │
│  layout/layoutRecursive (dwindle)  │
│  command/* (one type per command)  │
│  server.swift (unix socket server) │
└───────────┬────────────────────────┘
            │ AXUIElementSetAttributeValue(kAXPosition/kAXSize)
            ▼
┌────────────────────────────────────┐
│ WindowServer + per-app Accessibility│
└────────────────────────────────────┘

Common (shared, no AppKit): cmdArgs parsers, ClientRequest/ServerAnswer,
Orientation, WorkspaceName, MonitorDescription, appMetadata
PrivateApi (C headers): _AXUIElementGetWindow — the single private symbol
```

## 1. Modules

| Module | Responsibility | Notes |
| --- | --- | --- |
| `HyperMacApp` | SwiftUI `@main App`; one `MenuBarExtra` scene. Calls `initAppBundle()` from its `init`. | Product name `HyperMacApp`; not used for release builds, which go through XcodeGen |
| `AppBundle` | Everything that touches AX or owns state: config, tree, layout, commands, socket server, observers | `@MainActor` for the tree; the socket server runs off-main and hops on |
| `Common` | Arg parsers and the wire model. No AppKit import. | Shared by engine and CLI so the CLI can parse/validate before connecting |
| `PrivateApi` | `_AXUIElementGetWindow(AXUIElement, UnsafeMutablePointer<CGWindowID>)` | Isolated so upstream behaviour changes in one place |
| `Cli` | Thin client. Parses args, opens the socket, prints the answer, maps exit code | Product name `hypermac` |

## 2. Tree model

```
Workspace                     (one per monitor, named, holds a root tiling container)
└── TilingContainer           (root, orientation .h or .v, layout = .dwindle)
    ├── TilingContainer       (nested split)
    │   ├── Window (MacWindow)
    │   └── Window
    └── Window
```

- `TreeNode` — base class. Holds `parent`, `children`, `adaptiveWeight`, an MRU stack of children, and
  the last applied physical/virtual rects. `getWeight(_:)` walks up to the nearest ancestor whose
  orientation matches the requested axis and returns that node's `adaptiveWeight`.
- `TilingContainer` — a split. Holds `_orientation` and `layout` (`Layout` has exactly one case,
  `.dwindle`, as of this version) and the normalization logic.
- `Window` / `MacWindow` — one AX window. Owns `windowId`, `isFullscreen`, and the AX setter used by
  the layout (`setAxFrame`).
- `Workspace` — one monitor's workspace. `getWeight(_:)` returns the monitor's visible dimension, which
  terminates the weight recursion.
- `MacosUnconventionalWindowsContainer` — parallel containers that hold minimized, native-fullscreen,
  popup and hidden-app windows. They are tracked but never tiled.
- `MruStack` on every container drives "most recently used child", used for insertion and focus.

Weights: a new node binds with `WEIGHT_AUTO`, which resolves to the mean weight of its new siblings
(so an untouched container stays evenly split at weight `1` each) or `1` when it is the first child.

## 3. Dwindle layout math

`Workspace.layoutWorkspace()` → `TilingContainer.layoutDwindle` → `layoutDwindleRecursive`.

```
box             = monitor.visibleRect padded by outer gaps, height − 1        (macOS refuses full-height)
splitVertically = box.width >= box.height                                    (equivalent to Hyprland's
                                                                             box.h * 1 > box.w test)
gap             = resolved inner gap along the split axis
children        split by index: left = children[0..<n/2], right = children[n/2...]

axis      = splitVertically ? .h : .v
leftW     = Σ left.getWeight(axis)
rightW    = Σ right.getWeight(axis)
fraction  = container.orientation == axis
              ? dwindleFraction(firstWeight: leftW, secondWeight: rightW)
              : 0.5

horizontal: leftWidth  = (box.width  − gap) * fraction
            rightWidth = (box.width  − gap) − leftWidth
vertical:   topHeight  = (box.height − gap) * fraction
            bottomHeight = (box.height − gap) − topHeight
```

`dwindleFraction` (`Sources/AppBundle/layout/layoutRecursive.swift`):

```
non-finite weight        → 0.5
each weight              → max(weight, 0)
sum == 0                 → 0.5
otherwise                → clamp(first / sum, 0.05 … 0.95)
```

Why the orientation guard exists: `getWeight(.h)` returns the weight of the nearest ancestor that
splits horizontally. When the container's own orientation differs from the axis chosen by the aspect
rule, that recursion escapes this container and would mix an ancestor's weight into a sibling's share.
Holding `0.5` in that case keeps the split even and the tree consistent.

Why non-positive weights are floored instead of resetting to `0.5`: `ResizeCommand` is
weight-conserving in absolute units — it adds `delta` to the target and subtracts
`delta / (n − 1)` from every sibling — so on a two-child container `resize smart +10` produces the
weights `11, −9`. Resetting to `0.5` would make the resize a no-op; flooring gives the target the
largest legal share (`0.95`) and leaves the sibling at the `0.05` floor, which is exactly the intent
of Hyprland's `0.1 … 1.9` clamp on `splitRatio`.

## 4. Applying frames (AX)

Layout is a pure computation followed by AX writes:

1. `Window.setAxFrame(topLeftCorner:size:)` delegates to `MacApp.setAxFrame`, which cancels any
   in-flight job for that `windowId`, schedules one `withWindowAsync` job that writes the position and
   then the size, and wraps the writes in `disableAnimations`. Order matters: size after position,
   because some apps jump when sized first (`MacWindow.swift`).
2. Writes are coalesced, not compared: a burst of layouts leaves only the newest frame per window
   pending, so the last computed geometry always wins and intermediate frames are never applied.
3. Each write is captured in the enclosing `runSession(...)`, which records the window as recently
   resized so the resulting AX notification does not trigger a second relayout.
4. `lastAppliedLayoutPhysicalRect` / `lastAppliedLayoutVirtualRect` are written for every node. Mouse
   resize uses the virtual rect (gaps as if zero) to convert pixel deltas into weight deltas.

### Permission flow

`checkAccessibilityPermissions()` runs before the socket server starts:

- `AXIsProcessTrustedWithOptions([axTrustedCheckOptionPrompt: true])` — macOS shows the grant dialog.
- On failure the engine calls `tccutil reset Accessibility <bundle-id>` for its own identifier, because
  re-signing an ad-hoc bundle otherwise leaves a permission that points at the old code signature, and
  then terminates. It never runs half-permissioned.

Because the grant is keyed to the bundle identifier, `dev.hypermac.HyperMac` is defined exactly once,
in `Sources/Common/appMetadata.swift`; every socket path, signpost subsystem and `tccutil` call derives
from it.

## 5. Configuration

TOML, parsed with TOMLKit. Discovery order (`Sources/AppBundle/config/ConfigFile.swift`):

| Order | Path | Applies to |
| --- | --- | --- |
| 1 | `--config-path <path>` | release and debug |
| 2 | `~/.hypermac.toml` | release |
| 3 | `$XDG_CONFIG_HOME/hypermac/hypermac.toml` (default `~/.config/…`) | release |
| 2′ | `~/.hypermac-debug.toml` | debug |
| 3′ | `$XDG_CONFIG_HOME/hypermac/hypermac-debug.toml` | debug |

Zero candidates → the bundled `Contents/Resources/default-config.toml` is used (falling back to
`docs/config-examples/default-config.toml` for non-bundled debug runs). More than one candidate →
`ambiguousConfigError`, reported instead of silently picking one.

Top-level keys: `after-login-command`, `after-startup-command`, `on-focus-changed`,
`on-focused-monitor-changed`, `enable-normalization-flatten-containers`,
`enable-normalization-opposite-orientation-for-nested-containers`, `default-root-container-layout`
(`dwindle`; the only implemented value), `default-root-container-orientation`
(`horizontal|vertical|auto`), `start-at-login`, `automatically-unhide-macos-hidden-apps`,
`exec-on-workspace-change`, `exec`, `gaps`, `workspace-to-monitor-force-assignment`,
`on-window-detected`, `non-empty-workspaces-root-containers-layout-on-startup`,
`indent-for-nested-containers-with-the-same-orientation`, plus `[mode.<id>.binding]` and `[key-mapping]`.

`reload-config` re-parses and swaps a `Config` value; parse errors are surfaced via a GUI alert naming
the offending key path and leave the previous config active.

## 6. IPC and CLI

```
transport   Unix domain socket, SOCK_STREAM
path        /tmp/<bundle-id>-<user>.sock
            release: dev.hypermac.HyperMac-<user>.sock
            debug:   dev.hypermac.HyperMac.debug-<user>.sock
framing     one JSON object per direction, no length prefix, connection stays open for one request
```

```jsonc
// client → server
{ "command": "focus left",        // legacy mirror of args, kept for old servers
  "args": ["focus", "left"],      // authoritative
  "stdin": "" }

// server → client
{ "exitCode": 0,
  "stdout": "",
  "stderr": "",
  "serverVersionAndHash": "0.1.0 <git-hash>" }
```

Server side (`server.swift`): a `DispatchQueue.global()` loop accepts connections; each connection is
handed to a `Task` that hops to `@MainActor` via `runSession(.socketServer, token)` before running the
parsed command. `parseCommand(args)` is shared with the CLI, so a syntactically invalid command is
rejected identically on both sides.

Gating: the server can be switched off (`hypermac enable off`). A disabled server answers with an
explicit "server is disabled, use 'hypermac enable on'" error rather than closing the socket, so the CLI
can tell "disabled" from "not running". Debug builds additionally send `enable off` to the release
server on startup to avoid two engines fighting over the same windows.

Version skew: the CLI compares `serverVersionAndHash` with its own build and warns instead of failing.

## 7. Concurrency

- The tree, config, focus and layout are `@MainActor`. `layoutWorkspace()` is `async` but resumed on the
  main actor; only AX syscalls block it briefly.
- The socket server runs on a background queue. Commands enter the main actor through
  `runSession(_:_:body:)` (`layout/refresh.swift`), which requires a `RunSessionGuard` — the token that
  encodes "the engine is enabled" — and is the only way a command is allowed to mutate the tree.
- AX and workspace notifications arrive through `GlobalObserver`, which hops to `@MainActor` and calls
  `runRefreshSession(...)`. That function cancels the active refresh task and replaces it, so a burst of
  window events collapses into a single refresh (`runRefreshSessionBlocking`) instead of a relayout per
  event.
- `closedWindowsCache` / `FrozenWorld` cursor: when the screen locks, the engine freezes the tree so
  that windows disappearing during the lock are not treated as closed.

## 8. Build and release

- `swift build --product hypermac` → CLI only, no AppKit, no Xcode.
- `swift build --product HyperMacApp` → menu-bar executable. It is a plain executable, not a bundle;
  to get a stable Accessibility grant it must be copied into an `.app` with the bundle identifier from
  `project.yml` and ad-hoc signed (`codesign --force --deep --sign -`).
- `./generate.sh --ignore-xcodeproj` regenerates `versionGenerated.swift` (and `gitHashGenerated.swift`)
  without XcodeGen. `--ignore-cmd-help` is required in this snapshot because the `docs/*.adoc` man-page
  sources that `script/generate-cmd-help.sh` reads are not part of the fork point; the committed
  `cmdHelpGenerated.swift` holds build stubs.
- `project.yml` is the source of truth for the release bundle (XcodeGen: `PRODUCT_NAME`,
  `PRODUCT_BUNDLE_IDENTIFIER`, entitlements path, `LSUIElement`, deployment target `13.0`,
  `SWIFT_VERSION 6.0`). Xcode is needed only to produce the `.xcodeproj`; nothing in the debug path
  depends on it.
- Toolchain: this pass was executed with the pinned Swift toolchain from `.swift-version` (`6.1.2`),
  installed from the swift.org `swift-6.1.2-RELEASE-osx.pkg` because `swiftly` 1.1.3/1.2.0 aborts
  (`freed pointer was not the last allocation`, exit 134) on this macOS build.

## 9. Test strategy

| Layer | Where | What it proves |
| --- | --- | --- |
| Pure functions | `AppBundleTests` | arg parsing, config parsing and error text, dwindle fraction, JSON shaping |
| Tree operations | `AppBundleTests/command/*` | `focus`/`move`/`swap`/`split`/`join`/`resize` semantics against a fake AX tree (`TestApp`, `TestWindow`) |
| Contract | `AppBundleTests/tree` | weight arithmetic and normalization invariants |
| Smoke (manual) | `docs/RUNBOOK.md` | two real TextEdit windows tile, `resize` changes frames, `layout dwindle` round-trips |

The dwindle parity rule is deliberately a `nonisolated static` function so it can be asserted without
constructing an AX tree, a window server, or an actor context:

```
swift test --filter DwindleFractionTest
```

## 10. Known parity gaps

| Hyprland behaviour | HyperMac | Status |
| --- | --- | --- |
| `dwindle:default_split_ratio` clamped to `0.1 … 1.9` | `dwindleFraction` clamp `0.05 … 0.95` (same interval after `f = r/(1+r)`) | ported, unit-tested |
| `splitRatio` per node, moved by `2·delta / box` on resize | per-node `adaptiveWeight`, moved by absolute weight units | ported in spirit; units differ, see §3 |
| aspect-ratio split direction (`box.h · multiplier > box.w`) | `width >= height` | ported (multiplier fixed at 1) |
| `dwindle:use_active_for_splits` | always the MRU child | **not implemented** |
| `dwindle:force_split` (forced direction) | always the aspect rule | **not implemented** |
| `dwindle:split_bias` (ratio inversion for child 0) | no inversion | **not implemented** |
| `dwindle:smart_split`, `preserve_split` | n/a — n-ary tree, no split history | **not implemented** |
| removal promotes the surviving sibling | same behaviour via tree unbind | ported |
