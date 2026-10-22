<img width="150" height="150" alt="HyprMac Fox Window Logo" src="https://github.com/user-attachments/assets/b67a7a42-6372-4e75-a166-0db03dc9d7a9" />

# HyperMac

HyperMac is a keyboard-driven tiling window manager for macOS. It reads the on-screen window
geometry of ordinary macOS apps through the Accessibility (AX) API and then moves and resizes those
windows into a tiling tree. Windows keep belonging to their own apps; HyperMac never hosts them.

**HyperMac is not a Wayland compositor and not a Desktop Environment.** There is no display server,
no protocol layer, no surface compositing and no window content of its own. The macOS WindowServer
remains the only compositor; HyperMac is a client of it, exactly like any other app.

The tiling model is a port of Hyprland's *dwindle* layout: every container splits along the longer
dimension of its box and hands each side a share of that box. HyperMac keeps its own n-ary container
tree, gap handling and TOML configuration, and adopts Hyprland's split-share rule so that a
container can be split unevenly and `resize` has a visible effect.

## Requirements

| Requirement | Detail |
| --- | --- |
| macOS | 13.0 (Ventura) or newer — the deployment target of the package |
| CPU | Apple Silicon or Intel |
| Toolchain | Swift 6.1.2 (`swift-tools-version: 6.0`, Swift 6 language mode) |
| Permission | Accessibility, granted to the assembled `HyperMac.app` in System Settings → Privacy & Security → Accessibility |
| Sandbox | Must stay **off**. The Accessibility API does not work inside an App Sandbox. |

Xcode is not required. The Swift Package builds the CLI and the app executable; XcodeGen is only
needed to produce the release `.xcodeproj`.

## Build

```sh
swift build --product hypermac      # CLI → .build/debug/hypermac
swift build --product HyperMacApp   # menu-bar app executable → .build/debug/HyperMacApp
swift test                          # unit tests
```

Assemble a runnable bundle (the app executable must be inside an `.app` so that macOS can attach a
stable bundle identifier to the Accessibility grant):

```sh
mkdir -p .build/HyperMac.app/Contents/MacOS
cp .build/debug/HyperMacApp .build/HyperMac.app/Contents/MacOS/
cp docs/config-examples/default-config.toml .build/HyperMac.app/Contents/Resources/default-config.toml
# Info.plist: CFBundleIdentifier dev.hypermac.HyperMac, CFBundleExecutable HyperMacApp, ...
codesign --force --deep --sign - .build/HyperMac.app
```

## Run and debug

```sh
open .build/HyperMac.app                 # start the engine (menu-bar agent, no Dock icon)
./.build/debug/hypermac enable on        # enable the command server
./.build/debug/hypermac list-windows     # talk to the running engine
./.build/debug/hypermac reload-config    # re-read the TOML file without restarting
```

`./run-cli.sh` wraps the CLI from `.debug/`, and `./run-debug.sh` starts the debug app.

## Configuration

HyperMac reads one TOML file. Resolution order, first match wins:

1. `--config-path <path>` passed to the app executable
2. `~/.hypermac.toml`
3. `$XDG_CONFIG_HOME/hypermac/hypermac.toml` (default `~/.config/hypermac/hypermac.toml`)

Debug builds look for `~/.hypermac-debug.toml` and `hypermac-debug.toml` instead. If more than one
candidate exists, HyperMac reports an ambiguity error rather than guessing. If no file exists, the
bundled `Contents/Resources/default-config.toml` is used.

Start from a copy of [`docs/config-examples/default-config.toml`](docs/config-examples/default-config.toml):

```sh
cp docs/config-examples/default-config.toml ~/.hypermac.toml
```

### Default keybindings (binding mode `main`)

| Keys | Command |
| --- | --- |
| `alt-h/j/k/l` | `focus left/down/up/right` |
| `alt-shift-h/j/k/l` | `move left/down/up/right` |
| `alt-minus` / `alt-equal` | `resize smart -50` / `resize smart +50` |
| `alt-1` … `alt-5` | `workspace 1` … `workspace 5` |
| `alt-shift-1` … `alt-shift-5` | `move-node-to-workspace 1` … `5` |
| `alt-tab` | `workspace-back-and-forth` |
| `alt-shift-tab` | `move-workspace-to-monitor --wrap-around next` |
| `alt-slash` | `layout dwindle horizontal vertical` |
| `alt-comma` | `layout dwindle` |
| `alt-shift-semicolon` | `mode service` |
| `alt-enter` | `exec-and-forget open -n -a "Ghostty"` |

Binding mode `service`: `esc` reloads the config, `r` flattens the workspace tree,
`f` toggles floating, `backspace` closes all windows but the current one.

## CLI examples

```sh
hypermac list-windows --all --format '%{window-id}%{tab}%{app-name} - %{window-title}'
hypermac list-workspaces --monitor all --empty no
hypermac focus --window-id 123456 left
hypermac move-node-to-workspace 2
hypermac resize smart +50
hypermac layout dwindle
hypermac config --get gaps.inner.horizontal --keys
hypermac mode service
hypermac debug-windows          # dump raw AX window frames, useful for bug reports
```

Every subcommand also exists as a config binding value, and `hypermac` reports its own version with
`-v`. The full command set is `Sources/Common/cmdArgs/impl/`.

## Documentation

- [docs/PRD.md](docs/PRD.md) — problem, users, goals, requirements, success criteria
- [docs/TRD.md](docs/TRD.md) — architecture, tree model, dwindle math, config and IPC contracts
- [docs/REVERSE-ENGINEERING.md](docs/REVERSE-ENGINEERING.md) — REA evidence from the Hyprland binary and the parity mapping
- [docs/RUNBOOK.md](docs/RUNBOOK.md) — install, permission grant, troubleshooting, uninstall
- [docs/evidence/hyprland-0.56.2-4-rea.json](docs/evidence/hyprland-0.56.2-4-rea.json) — retained REA evidence bundle

## Known gaps

- **Icon.** `resources/Assets.xcassets/AppIcon.appiconset` ships the upstream HyprSpace artwork. The
  pixels are unchanged; only the embedded metadata strings were rebranded. Replacing the artwork is
  outstanding work.
- **Insertion-point parity.** Hyprland's `use_active_for_splits`, forced `force_split` direction and
  `split_bias` are not implemented. HyperMac always inserts at the most recently used position.
- **Resize units.** `resize` moves container weights, not pixels. See [docs/TRD.md](docs/TRD.md).

## Attribution

HyperMac is a fork of [HyprSpace](https://github.com/patroza/HyprSpace) (MIT, Copyright (c) 2023
Nikita Barut), which in turn derives its tiling model and CLI shape from
[AeroSpace](https://github.com/nikitabobko/AeroSpace) (MIT). The upstream source is kept as the
`upstream` git remote; the fork point is commit `e70e6306b2`.

The dwindle split-share rule was derived from the released Hyprland binary
(`hyprland 0.56.2-4`, Arch Linux x86_64) with REA. See
[docs/REVERSE-ENGINEERING.md](docs/REVERSE-ENGINEERING.md).

Third-party licenses are collected in [`legal/`](legal/README.md).
