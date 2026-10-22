# HyperMac — Product Requirements Document

## 1. Problem

macOS ships a stacking window manager. Users who want Hyprland-style tiling have three options, all
with a cost:

- **Replace the desktop**: run a Wayland compositor in a VM or on Linux. Loses every macOS app.
- **Learn a separate tiling app's model**: most macOS tilers use i3-style manual containers or
  fixed grids; none reproduce Hyprland's dwindle split behaviour or its keybinding/config shape.
- **Live without it**: drag windows by hand.

HyperMac's problem statement: *give macOS users Hyprland's dwindle tiling model and configuration
ergonomics on top of the existing WindowServer, with no display-server replacement and no loss of
native apps.*

Constraints that make this non-trivial:

1. macOS offers no window-management hook. The only sanctioned control surface is the Accessibility
   API, which can read and set another app's window frame but knows nothing about tiling.
2. Any window can be moved by the user or the app at any time, so the tiling tree must be
   reconstructed from observed state, not assumed.
3. `resize` semantics only exist if the layout honours per-node shares. Upstream HyprSpace hard-codes
   a 50/50 split, so `resize` had no visible effect. Closing that gap is a product requirement, not
   a cosmetic one.

## 2. Target user

- Developers and power users who already know Hyprland, i3 or AeroSpace keybindings.
- Users with one large monitor or a laptop plus external display, who tile 4–12 windows.
- Users who accept a menu-bar agent with an Accessibility grant in exchange for keyboard-only window
  management.

Explicitly not the target user: someone who wants animated, physics-driven or mouse-first window
movement; someone who cannot grant Accessibility permission; someone who wants a sandboxed app.

## 3. Goals

- G1 — Tile ordinary macOS windows with a dwindle layout that reproduces Hyprland's split-share rule.
- G2 — Make layout state durable: workspaces, per-monitor assignment, and per-container orientation
  survive focus changes, window churn and config reloads.
- G3 — Expose the whole engine through a scriptable CLI so that everything a keybinding can do, a
  shell script can do, and vice versa.
- G4 — Never require Xcode to build or run the engine.
- G5 — Be honest about parity: what is ported from Hyprland must be backed by binary evidence, and
  what is not ported must be listed as a gap.

## 4. Non-goals

| Non-goal | Why |
| --- | --- |
| Wayland protocols / a compositor | macOS has no Wayland surface protocol; HyperMac is a WindowServer client |
| Surface compositing, damage tracking, frame pacing | Owned by WindowServer; not addressable from an AX client |
| Animations and transitions | AX frame sets are not frame-synchronised; any animation would be a series of jumps |
| Plugins / scripting host beyond the CLI | The CLI already covers automation; a plugin ABI is unmaintainable in this codebase |
| XWayland / X11 app support | There is no X server on macOS |
| Notarization, Developer ID, Homebrew cask | Out of scope for this pass; ad-hoc signing is enough for local use |
| Replacing the app icon artwork | Tracked as a known branding gap, see [RUNBOOK.md](RUNBOOK.md) |

## 5. Functional requirements

**FR-1 Dwindle tiling.** Every tiling container splits its box along the longer dimension (width ≥
height ⇒ vertical split), assigns children to the two sides, and subtracts configured inner gaps from
the split box. A single child occupies the whole box.

**FR-2 Weighted split parity.** The share of the split box given to the first side is a function of
the container weights along the split axis, not a constant:

```
fraction = clamp(firstWeight / (firstWeight + secondWeight), 0.05 … 0.95)
```

Non-finite weights fall back to `0.5`; non-positive weights are floored at zero so a weight-conserving
`resize` cannot revert the split to an even one. This is the fraction form of Hyprland's
`splitRatio ∈ 0.1 … 1.9`. Evidence: [REVERSE-ENGINEERING.md](REVERSE-ENGINEERING.md).

**FR-3 Workspaces.** Named workspaces exist per monitor, are created on demand from bindings or
`move-node-to-workspace`, can be flattened on demand, and are garbage-collected when empty. The
`workspace-back-and-forth` and `move-workspace-to-monitor --wrap-around` commands must work across
monitors.

**FR-4 Multi-monitor.** Windows, workspaces and gaps are monitor-scoped. `gaps.outer.*` may be a
constant, a per-monitor map or a mixed list. Windows must never be laid out outside
`monitor.visibleRect` padded by the outer gaps.

**FR-5 Configuration and bindings.** A single TOML file drives gaps, binding modes, per-mode
keybindings, `on-window-detected` matchers, `workspace-to-monitor-force-assignment`, startup and
login hooks. Reloading the config (`reload-config`, or `esc` in the `service` mode) applies changes
without restarting; a config error must be reported in the GUI and must not kill the engine.

**FR-6 Floating and native macOS states.** Any window can be toggled between tiling and floating.
Native fullscreen, native minimize and native hidden-app windows must be tracked but excluded from
tiling, and must return to their slot when they come back.

**FR-7 Accessibility permission flow.** On startup the engine must prompt for Accessibility, and if
the permission is absent must demolish the stale TCC entry for its own bundle identifier so that
re-signing the ad-hoc bundle does not leave a broken grant, then terminate. It must never run
half-permissioned.

**FR-8 IPC and CLI.** A CLI process talks to the running engine over a Unix-domain socket at
`/tmp/<bundle-id>-<user>.sock`, sending one JSON request and reading one JSON answer. The server can be
disabled (`enable off`) so that it refuses commands, and the CLI must distinguish "server disabled"
from "server not running".

## 6. Success criteria

| # | Criterion | Verification |
| --- | --- | --- |
| SC-1 | CLI and app build with no Xcode | `swift build --product hypermac` and `swift build --product HyperMacApp` exit 0 |
| SC-2 | Split-share parity is unit-tested | `swift test --filter DwindleFractionTest` exits 0 |
| SC-3 | Rebrand is complete | `git grep -n -i hypermac`-level audit: no `hyprspace` left outside licence and upstream attribution lines |
| SC-4 | Resize has a visible effect | two tiled windows → `hypermac resize smart +10` → target frame grows, sibling shrinks, both inside the monitor's visible rect |
| SC-5 | Layout command round-trips | `hypermac layout dwindle` exits 0 and both windows stay tiled |
| SC-6 | Evidence is complete | every parity claim in [REVERSE-ENGINEERING.md](REVERSE-ENGINEERING.md) carries an Evidence ID; no claim is labelled observed without one |
| SC-7 | Docs are complete | PRD, TRD, REVERSE-ENGINEERING, RUNBOOK exist with every section written out and are linked from README |

## 7. Constraints

- **Accessibility API only.** No private window-server calls beyond `_AXUIElementGetWindow`, which is
  already isolated in `Sources/PrivateApi`.
- **macOS 13 deployment target.** No macOS 14+ API without an availability guard.
- **App Sandbox disabled.** `com.apple.security.app-sandbox = false` is required; a sandboxed app
  cannot manipulate other apps' windows.
- **Stable bundle identifier.** Accessibility grants are keyed to `dev.hypermac.HyperMac`; changing it
  invalidates every existing grant.
- **Swift 6 language mode.** Strict concurrency; the tiling tree is `@MainActor`-isolated and the
  socket server hops onto the main actor to run commands.
- **Weight-based resize.** `resize` takes integer weight units, not pixels. Documented in
  [TRD.md](TRD.md); out of scope to change.
