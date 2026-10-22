# HyperMac — Runbook

Everything here is executed from the repository root.

## 1. Prerequisites

```sh
xcode-select -p            # /Library/Developer/CommandLineTools is enough
sw_vers -productVersion    # 13.0 or newer
uname -m                   # arm64 or x86_64
```

No Xcode, no Nix, no Homebrew requirement. The one non-negotiable is a Swift 6 toolchain: the package
declares `swift-tools-version: 6.0` and builds in Swift 6 language mode.

## 2. Toolchain

The pinned version is in `.swift-version` (`6.1.2`).

Preferred:

```sh
swiftly install 6.1.2
swiftly use 6.1.2
swift --version            # Swift version 6.1.2 ...
```

**Known failure — swiftly aborts on this macOS build.** Both swiftly 1.1.3 and 1.2.0 abort with
`freed pointer was not the last allocation` (exit 134) on `swiftly list` / `swiftly install`. Install
the pinned toolchain from swift.org instead.

```sh
cd /tmp
curl -fL -o swift-6.1.2-RELEASE-osx.pkg \
  https://download.swift.org/swift-6.1.2-release/xcode/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-osx.pkg
# 1530375397 bytes — check it before trusting it
stat -f%z swift-6.1.2-RELEASE-osx.pkg
```

`pkgutil --expand-full` on this package reports `archive verify failed` on this machine even when the
payload is intact, so the toolchain is taken straight out of the XAR heap. The offsets below come from
`xar --dump-toc` and are **heap-relative**:

| member | heap offset | length |
| --- | --- | --- |
| `Payload` | 311852 | 1530057501 |
| header + TOC | — | 4504 (heap starts at absolute `4504`) |

```sh
python3 - <<'PY'
src='swift-6.1.2-RELEASE-osx.pkg'; dst='/tmp/payload.gz'
PSTART=4504+311852; LEN=1530057501
with open(src,'rb') as f, open(dst,'wb') as o:
    f.seek(PSTART); left=LEN
    while left:
        b=f.read(min(1<<22,left))
        if not b: break
        o.write(b); left-=len(b)
PY
gzip -t /tmp/payload.gz          # must be silent; any "data stream error" means a bad download
mkdir -p /tmp/swift-tc && bsdtar -xzf /tmp/payload.gz -C /tmp/swift-tc
export PATH="/tmp/swift-tc/usr/bin:$PATH"
swift --version                  # Swift version 6.1.2 (swift-6.1.2-RELEASE)
```

The payload is flat: the toolchain lands in `/tmp/swift-tc/usr/bin` (5.4 GB extracted), **not** under
`Developer/Toolchains/`. The system SDK at
`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk` is picked up automatically.

Verify the download before extracting anything: `gzip -t` failing means bytes are wrong and no amount
of re-running the installer will help. Re-fetch the failing byte range rather than the whole 1.4 GB:

```sh
# absolute offset of the failure = 316356 + <offset reported by gzip/inflate>
curl -fsS -r 1186000000-1530373857 -o /tmp/win.bin <pkg-url>
# then dd the window into the package at that offset
```

To make the toolchain permanent, move `/tmp/swift-tc` somewhere stable (for example
`~/Library/Developer/swift-6.1.2`) and add its `usr/bin` to `PATH` in your shell profile. Keep the whole
tree: `swift` resolves its standard library, platform headers and `clang` resources relative to itself.


`generate.sh` and `script/setup.sh` prefer `swiftly run swift`; with a broken swiftly, either fix
`PATH` so `swiftly` is absent (the scripts then fall back to plain `swift`) or invoke `swift` directly.

## 3. Build

```sh
swift build --product hypermac       # → .build/debug/hypermac
swift build --product HyperMacApp    # → .build/debug/HyperMacApp
swift test                           # unit tests
swift test --filter DwindleFractionTest
```

Regenerate the version symbol without XcodeGen:

```sh
./generate.sh --ignore-xcodeproj --ignore-cmd-help
```

`--ignore-cmd-help` is required in this fork point: `docs/*.adoc` man-page sources are absent, so
`script/generate-cmd-help.sh` would overwrite `Sources/Common/cmdHelpGenerated.swift` with an empty
file and break the build. `do not run build-docs.sh` (needs Ruby + Bundler + asciidoctor).

## 4. Assemble the app bundle by hand

The Accessibility grant is keyed to a bundle identifier, so the executable must live inside an `.app`.

```sh
rm -rf .build/HyperMac.app
mkdir -p .build/HyperMac.app/Contents/MacOS .build/HyperMac.app/Contents/Resources
cp .build/debug/HyperMacApp .build/HyperMac.app/Contents/MacOS/HyperMacApp
cp docs/config-examples/default-config.toml .build/HyperMac.app/Contents/Resources/default-config.toml
cat > .build/HyperMac.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.hypermac.HyperMac</string>
  <key>CFBundleExecutable</key><string>HyperMacApp</string>
  <key>CFBundleName</key><string>HyperMac</string>
  <key>CFBundleDisplayName</key><string>HyperMac</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict></plist>
PLIST
codesign --force --deep --sign - .build/HyperMac.app
codesign -v .build/HyperMac.app
```

Re-run `codesign` after every rebuild; a re-signed binary with the same identifier usually keeps its
grant, but a changed signature may require the reset in §5.

For a grant that survives `swift build` cleanups, install to `~/Applications`:

```sh
ditto .build/HyperMac.app ~/Applications/HyperMac.app
```

## 5. Accessibility permission

1. `open ~/Applications/HyperMac.app` (or `.build/HyperMac.app`).
2. macOS prompts; accept. If it does not prompt: System Settings → Privacy & Security → Accessibility
   → `+` → select `HyperMac.app`.
3. Verify:

```sh
./.build/debug/hypermac enable on     # exit 0 means the engine answered on the socket
```

The engine itself resets a broken grant with `tccutil reset Accessibility dev.hypermac.HyperMac` and
exits when it is not trusted, because an ad-hoc re-sign can leave a grant pointing at a dead signature.
To reset manually:

```sh
tccutil reset Accessibility dev.hypermac.HyperMac
killall HyperMacApp 2>/dev/null
open ~/Applications/HyperMac.app
```

Debug builds use the identifier `dev.hypermac.HyperMac.debug`:

```sh
tccutil reset Accessibility dev.hypermac.HyperMac.debug
```

`./script/reset-accessibility-permission-for-debug.sh` does exactly that.

## 6. Start, stop, inspect

```sh
open ~/Applications/HyperMac.app          # start (menu-bar agent, no Dock icon)
pgrep -fl HyperMacApp                     # is it up?
./.build/debug/hypermac list-windows      # engine answers?
killall HyperMacApp                       # stop
```

`./.build/debug/hypermac enable off` keeps the engine running but makes it refuse commands — useful
when another tiler should own the windows temporarily. A debug build additionally sends `enable off`
to the release engine at startup, so never run both and expect the release one to keep working.

## 7. Configuration

```sh
cp docs/config-examples/default-config.toml ~/.hypermac.toml
$EDITOR ~/.hypermac.toml
./.build/debug/hypermac reload-config     # apply without restart
```

Resolution order and debug file names are in [TRD.md](TRD.md) §5. If both `~/.hypermac.toml` and
`~/.config/hypermac/hypermac.toml` exist, the engine reports an ambiguity error and keeps the previous
config — delete one.

## 8. Troubleshooting

### `Can't connect to HyperMac server. Is HyperMac.app running?`

Check the socket path and the bundle identifier first:

```sh
ls -l /tmp/dev.hypermac.HyperMac-$USER.sock        # release build
ls -l /tmp/dev.hypermac.HyperMac.debug-$USER.sock  # debug build
```

- No file → the engine is not running, or it aborted before `startUnixSocketServer()`. Check
  Console.app for `HyperMacApp`.
- File exists but connection is refused → a stale socket from a killed process:
  `rm /tmp/dev.hypermac.HyperMac-$USER.sock`, then restart the app.
- Wrong identifier → the binary was built from a different bundle identifier than the CLI expects.
  Both derive from `Sources/Common/appMetadata.swift`; rebuild both.

### `HyperMac server is disabled and doesn't accept commands`

```sh
./.build/debug/hypermac enable on
```

### Windows do not move at all

Accessibility is not granted to *this* bundle. See §5. Granting it to the CLI is not enough — the CLI
only sends commands; the engine performs the AX writes.

### Windows jump back immediately

Another window manager (Rectangle, Magnet, Amethyst, a second HyperMac instance) is competing:

```sh
pgrep -fl 'HyperMacApp|Rectangle|Magnet|Amethyst'
./.build/debug/hypermac enable off
```

### `layout dwindle` reports a parse error

`layout` takes a comma-free list of tokens drawn from `dwindle|horizontal|vertical|tiling|floating`.
`layout dwindle` alone is valid; `layout dwindle,horizontal` is not.

### Layout looks messy, or windows do not fill the monitor

Two separate causes, both recoverable without restarting:

1. **The tree was polluted by floating / native-fullscreen / hidden windows.** A native-fullscreen
   window gets its own macOS Space, and `layout` then answers `The window is non-tiling` or
   `Can't change layout for macOS minimized, fullscreen windows or windows or hidden apps`.
   Leave native fullscreen (⌃⌘F), activate the app so it is not in the hidden-apps container, then:

   ```sh
   ./.build/debug/hypermac flatten-workspace-tree   # drop the nesting, one flat container
   ./.build/debug/hypermac layout tiling
   ./.build/debug/hypermac balance-sizes            # reset all weights to equal
   ```

2. **`resize` overshot.** `resize` moves container **weights**, not pixels, and it is
   weight-conserving in absolute units. With the default weight `1` per window, `resize smart +10` on a
   two-window split produces the weights `11, -9`; the non-positive sibling is floored and the clamp
   lands the target on the `0.95` share. On five windows it is worse: the target gets almost everything
   and the siblings are squeezed to the `0.05` floor, which reads as a collapsed layout. Observed on
   this machine: five equal 405 px columns became five ~100 px columns after one `resize smart +10`.

   Recover with `balance-sizes` (or `flatten-workspace-tree`). Prefer `resize smart 2` (set the
   absolute weight) over large relative steps, and remember a single weight step is proportional to the
   whole container, not to a window.

## 9. Uninstall

```sh
killall HyperMacApp 2>/dev/null
rm -rf ~/Applications/HyperMac.app .build/HyperMac.app
tccutil reset Accessibility dev.hypermac.HyperMac
tccutil reset Accessibility dev.hypermac.HyperMac.debug
rm -f ~/Library/LaunchAgents/dev.hypermac.HyperMac.plist   # only if start-at-login was enabled
rm -f ~/.hypermac.toml ~/.hypermac-debug.toml
rm -rf ~/.config/hypermac
rm -f /tmp/dev.hypermac.HyperMac-$USER.sock /tmp/dev.hypermac.HyperMac.debug-$USER.sock
```

## 10. Known branding gap

`resources/Assets.xcassets/AppIcon.appiconset` still ships the upstream HyprSpace artwork. Only the
embedded PNG metadata strings were rebranded; **the pixels are unchanged**. Anybody replacing the icon
must regenerate every size in that folder (`icon_16x16` … `icon_512x512@2x`) plus `icon.png` and
`icon_1024x1024.png`, and keep the file names, or the asset catalog stops resolving and the app falls
back to a blank icon.

## 11. Refreshing the reverse-engineering evidence

The retained bundle is `docs/evidence/hyprland-0.56.2-4-rea.json`. To regenerate it:

```sh
mkdir -p artifacts
curl -fL -o artifacts/hyprland-0.56.2-4-x86_64.pkg.tar.zst \
  https://geo.mirror.pkgbuild.com/extra/os/x86_64/hyprland-0.56.2-4-x86_64.pkg.tar.zst
shasum -a 256 artifacts/hyprland-0.56.2-4-x86_64.pkg.tar.zst   # compare with docs/REVERSE-ENGINEERING.md
mkdir -p artifacts/hyprland-bin
bsdtar -xf artifacts/hyprland-0.56.2-4-x86_64.pkg.tar.zst -C artifacts/hyprland-bin \
  --include 'usr/bin/Hyprland'
file artifacts/hyprland-bin/usr/bin/Hyprland                  # ELF 64-bit LSB pie executable, x86-64
```

Extract **only** `usr/bin/Hyprland`: macOS volumes are case-insensitive by default, so extracting the
whole package puts `usr/bin/Hyprland` and the `usr/bin/hyprland` symlink at the same path and the
symlink wins, leaving a broken link instead of the binary.

Then re-run the REA commands recorded in [REVERSE-ENGINEERING.md](REVERSE-ENGINEERING.md) and overwrite
the JSON bundle. `artifacts/` is git-ignored; only the extracted digests and the Evidence bundle are
committed.

### REA environment notes

- The MCP server entry in `~/.omp/agent/mcp.json` launches a pinned install at
  `~/.rea-bootstrap/node_modules/rea-agents/scripts/rea.mjs` with an npm override pinning
  `@modelcontextprotocol/client` to `2.2.0`. Without the override, `rea-agents@6.5.0` crashes with
  `ERR_MODULE_NOT_FOUND` because the cached `2.3.1` client ships `index.cjs` but exports
  `index.mjs`.
- The same commands work from the CLI: `node ~/.rea-bootstrap/node_modules/rea-agents/scripts/rea.mjs`.
- Hopper's launcher locates the app through Spotlight and falls back to
  `/Applications/Hopper Disassembler.app`. If Spotlight indexing is disabled (`mdutil -s /` reports
  `Indexing disabled`) the fallback is the only path, so the app must be reachable at that exact
  location — a symlink is not enough, copy the bundle.
- Hopper's `hopper` helper cannot launch the app itself in this environment
  (`Cannot launch Hopper! The handler some object is not defined.`); start Hopper first with
  `open -a "/Applications/Hopper Disassembler.app"`.
- Hopper opens a modal loader-options dialog unless every loader is named explicitly, and `-Y` script
  execution only starts after the initial analysis finishes. For a 16 MB stripped ELF that exceeds
  REA's default startup budget; raise it with `REA_HOPPER_STARTUP_TIMEOUT_MS`.
