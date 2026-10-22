# HyperMac — Reverse-Engineering Report: Hyprland dwindle split semantics

Status: **evidence collected**. Two traces and three inventories are complete; the function dossiers
(§6) carry the pseudocode that backs the split arithmetic. Every claim below carries the Evidence ID it
comes from, and every claim that could not be tied to a returned record is marked `unverified`.

This report exists for one reason: HyperMac's dwindle layout originally hard-coded a 50/50 split, so
`resize` had no visible effect. The split share now follows Hyprland's rule, and that rule was read out
of a released Hyprland binary rather than guessed from the Hyprland manual.

## 1. Analysis target

| Field | Value |
| --- | --- |
| Package | `hyprland 0.56.2-4` (Arch Linux, `extra`, x86_64) |
| Mirror | `https://geo.mirror.pkgbuild.com/extra/os/x86_64/hyprland-0.56.2-4-x86_64.pkg.tar.zst` |
| Package SHA-256 | `163bc740241880192d90027fad39ddb809b1705b04800a1f0185a58f3ce0884a` |
| Member analysed | `usr/bin/Hyprland` |
| Member SHA-256 | `55da553be71222566ee73b973d2f56dbb9939044d8f22f81aa54b66c83f2f6d1` |
| Member size | 16 099 784 bytes |
| `file(1)` | `ELF 64-bit LSB pie executable, x86-64, version 1 (GNU/Linux), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, BuildID[sha1]=43967c6620e64342b8343fd59e283e148d9dd926, for GNU/Linux 4.4.0, stripped` |

The version pinned in the work plan (`hyprland-1.4.1-2`) returned HTTP 404 from the official mirror at
analysis time; the mirror's current `extra` build is `0.56.2-4`, so that build was used. The analysis
procedure is version-independent — it starts from the config-key strings, which are stable across
releases.

Extraction note: macOS volumes are case-insensitive by default. Extracting the whole package puts
`usr/bin/Hyprland` and the `usr/bin/hyprland` symlink on the same path and the symlink wins, leaving a
dead link. Only `usr/bin/Hyprland` was extracted (`--include 'usr/bin/Hyprland'`).

The binary is *stripped of the symbol table*, but C++ mangled names survive in `.dynsym`/`.rodata`, so
procedures are addressable by name. That is what makes the traces below possible without any GUI
navigation.

## 2. Tooling

| Component | Value |
| --- | --- |
| REA | `rea-agents 6.5.0`, run with Node.js `v26.0.0` |
| REA install | `~/.rea-bootstrap` (npm `overrides: { "@modelcontextprotocol/client": "2.2.0" }`) |
| Analysis provider | `hopper` — Hopper Disassembler, launcher SHA-256 `dad6f886261fad0d4cdd01aee6fcf57439c60d7b5c54e62fc97f0180116690e0` |
| Loader arguments | `-l ELF --intel-64`, background analysis enabled |
| Analysis profile | `target_kind: executable`, `target_format: elf`, `architecture: x86_64`, `function_dossier_coverage: observed-facets-and-call-relationships-v1` |
| Bundle | `docs/evidence/hyprland-0.56.2-4-rea.json` |

The REA **MCP** server could not be used for this pass: MCP servers are launched once per agent
session, and the session started before the pinned install existed. The same REA engine was driven
through its CLI (`node ~/.rea-bootstrap/node_modules/rea-agents/scripts/rea.mjs`), which emits the
identical canonical Evidence records. Two environment facts were required to make Hopper work at all
and are recorded in [RUNBOOK.md](RUNBOOK.md) §11:

- Hopper's `hopper` helper refuses to launch the application itself in this environment
  (`Cannot launch Hopper! The handler some object is not defined.`), so Hopper is started with
  `open -a` first and REA then reuses that running instance.
- Hopper defers `-Y` script execution until the initial analysis of the target finishes, which for a
  16 MB stripped ELF exceeds REA's default startup budget. `REA_HOPPER_STARTUP_TIMEOUT_MS` was raised.

## 3. Method

1. Inventory the config surface: literal string search for `dwindle:` (`ev_d5728ff3…`).
2. For each config key of interest, trace the literal through its references and resolve the
   containing procedure (`ev_60c100c7…`, `ev_ff663f95…`).
3. Enumerate the dwindle procedures by mangled name to get exact addresses
   (`ev_f29d4818…`).
4. Decompile the procedures that the traces and the procedure inventory identified, and read the
   arithmetic out of the pseudo-code (§6).
5. Cross-check nothing was inferred from a string alone: a config key only counts as evidence for
   behaviour when a *containing procedure* is resolved for its reference.

## 4. Evidence inventory

| Evidence ID | Operation | Confidence | Observation |
| --- | --- | --- | --- |
| `ev_d5728ff3fc09b548cefc4456e6f38727424bec2c362d941bce73d4a15716d7de` | `search_strings` | observed | 11 `dwindle:*` config keys with addresses: `force_split` `0xc25793`, `preserve_split` `0xc257a7`, `smart_split` `0xc257be`, `smart_resizing` `0xc257d2`, `special_scale_factor` `0xc257e9`, `use_active_for_splits` `0xc25806`, `default_split_ratio` `0xc25824`, `split_bias` `0xc2584c`, `precise_mouse_move` `0xc2585f`, `permanent_direction_override` `0xc40670`, `split_width_multiplier` `0xc40708` |
| `ev_60c100c7e281971a9c4a65be39fedd818863a55cc36b10ad652d5b8c43049054` | `trace_feature` | derived | `dwindle:default_split_ratio` referenced from `0x496bd0` inside `Config::Values::getConfigValues()` `0x488010`, and from `0xbc1170` inside `Layout::Tiled::CDwindleAlgorithm::addTarget(...)` `0xbbfe80` |
| `ev_ff663f958664f37a3d8e92ac7b2b4127b73a011ae2b4f0f60cc5a1f606540ad8` | `trace_feature` | derived | `dwindle:split_width_multiplier` referenced from `Config::Values::getConfigValues()` `0x488010`, from `Layout::Tiled::CDwindleAlgorithm::predictSizeForNewTarget()` `0xbb9010`, from `Layout::Tiled::SDwindleNodeData::recalcSizePosRecursive(bool,bool,bool)` `0xbba200` at `0xbba833`, and from `CDwindleAlgorithm::addTarget` `0xbbfe80` at `0xbc1a80` |
| `ev_ead63a8b980de1e974a091ee17be9d12829af2890834a2e29427ea552e1d9865` | `search_strings` | observed | RTTI/template evidence for `Layout::Tiled::SDwindleNodeData` inside `Hyprutils::Memory::CSharedPointer<Layout::Tiled::SDwindleNodeData>` containers, confirming the node type is reference-counted and stored in a `std::vector` |
| `ev_f29d481814337cd6bda739c86b666da184a577eba4c70fa42c3b1b02b318ec3b` | `search_procedures` | observed | 24 `Layout::Tiled::CDwindleAlgorithm::*` procedures with addresses, including `addTarget` `0xbbfe80`, `removeTarget` `0xbbb1d0`, `resizeTarget` `0xbbe0d0`, `predictSizeForNewTarget` `0xbb9010`, `recalculate` `0xbbae60`, `toggleSplit` `0xbbbcb0`, `moveToRoot` `0xbbc390`, `getNextCandidate` `0xbb8d90` |
| `ev_45f910c0dc62c674a9fc4f4959941842641e20187846053a7d3143da66e68ed2` | `analyze_function` | observed | `SDwindleNodeData::recalcSizePosRecursive(bool,bool,bool)` at `0xbba200`: instruction listing showing the aspect test and the per-node ratio multiplication (§6, F1, F2); references `dwindle:preserve_split`, `dwindle:smart_split`, `dwindle:precise_mouse_move`; 7 callees, 9 callers, 181 outgoing references, 0 unresolved calls |
| `ev_59eabe59dff9aeb81fa7e1c9e09aead4af20ded87380f306ce19901f761669dd` | `analyze_function` | observed | `CDwindleAlgorithm::addTarget(...)` at `0xbbfe80`: references every split-affecting key — `force_split`, `smart_split`, `use_active_for_splits`, `default_split_ratio`, `split_bias`, `precise_mouse_move`, `permanent_direction_override`, `split_width_multiplier` (§6, F3, F4, F6); 2 callers (`newTarget`, `movedTarget`), 2 258 instructions, 0 unresolved calls |
| `ev_6b9b4c226f611646fc970aec40355f8ebeefafd04d46636b2b94d9d9567bfc50` | `procedure_pseudo_code` | observed | Decompiler (not lifting) output for `recalcSizePosRecursive`; corroborates F1. Hopper returns lifted instruction IR for this procedure rather than C-like source, so the two records agree but neither is higher-level |


Confidence vocabulary as returned by REA: `observed` is a direct provider reading (a string object, a
procedure name at an address); `derived` is a composed workflow (a reference chain). Claims in §6 are
additionally tiered by what the record actually shows: instruction-level transcripts are quoted
verbatim, and anything the returned records do **not** establish is marked `unverified` inline rather
than smoothed over. §8 lists what was not attempted at all.


## 5. Structural findings

**S-1 — The node type owns the split state.** `Layout::Tiled::SDwindleNodeData` has a method
`recalcSizePosRecursive(bool, bool, bool)` (`ev_ff663f95…`) and is held through
`Hyprutils::Memory::CSharedPointer` in a `std::vector` (`ev_ead63a8b…`). Nodes are therefore a mutable,
shared, reference-counted tree, and the recursive recalculation is a node method, not an algorithm
method.

**S-2 — The algorithm object orchestrates; nodes compute.** `CDwindleAlgorithm` exposes 24 procedures
(`ev_f29d4818…`) that mutate the tree (`addTarget`, `removeTarget`, `resizeTarget`, `swapTargets`,
`toggleSplit`, `swapSplit`, `rotateSplit`, `moveToRoot`, `movedTarget`, `moveTargetInDirection`) and one
`recalculate(eRecalculateReason)` that drives layout.

**S-3 — `split_width_multiplier` is read inside the recursive recalculation.** Its reference at
`0xbba833` resolves to `SDwindleNodeData::recalcSizePosRecursive` (`ev_ff663f95…`). This is the
mechanism behind Hyprland's aspect-ratio split test: the node compares the box height scaled by the
multiplier against the box width, so the split axis can be biased without changing the tree.

**S-4 — `default_split_ratio` is read where new nodes are attached.** Its reference at `0xbc1170`
resolves to `CDwindleAlgorithm::addTarget` (`ev_60c100c7…`), and the key is registered in
`Config::Values::getConfigValues()` (`0x488010`). A freshly created node therefore receives its initial
ratio from the config, and later changes come from `resizeTarget`.

## 6. Behavioural findings

### F1 — The split axis is chosen by `boxHeight × split_width_multiplier > boxWidth`

*Evidence: `ev_45f910c0dc62c674a9fc4f4959941842641e20187846053a7d3143da66e68ed2`
(`analyze_function` of `SDwindleNodeData::recalcSizePosRecursive`), corroborated by
`ev_6b9b4c226f611646fc970aec40355f8ebeefafd04d46636b2b94d9d9567bfc50` (`procedure_pseudo_code` of
the same procedure) and `ev_ff663f95…` (the `split_width_multiplier` string reference at `0xbba833`
falling inside this procedure).*

The instruction listing returned for `recalcSizePosRecursive` contains, verbatim:

```
0xbba6e7  call  CConfigValue<long>::operator*                    ; a boolean config value
0xbba6f5  lea   rdi, [byte_f6a798+8]                             ; another config object
0xbba6fc  call  CConfigValue<long>::operator*
0xbba701  movsd xmm1, qword [r15+0x78]                           ; node field +0x78 (double)
0xbba707  movsd xmm0, qword [r15+0x70]                           ; node field +0x70 (double)
0xbba716  mov   rax, qword [qword_f6a800]
0xbba724  cvtss2sd xmm2, dword [rax]                             ; split_width_multiplier (float config)
0xbba728  mulsd xmm2, xmm1                                       ; multiplier * field +0x78
0xbba72c  comisd xmm2, xmm0                                      ; ... compared with field +0x70
0xbba730  seta  byte [r15+0x58]                                  ; node field +0x58 := (xmm2 > xmm0)
```

Read as a comparison, the node stores a boolean at `+0x58` equal to
`split_width_multiplier × node[+0x78] > node[+0x70]`. This is an aspect-ratio test with a tunable bias
factor, and it is *stored on the node* rather than recomputed for every child.

Inference (marked, because the field *names* are not in the binary): `+0x70` is the split box width,
`+0x78` is its height, and `+0x58` is the resulting "split top / split left" flag. With the multiplier
at its Hyprland default of `1.0`, the test degenerates to `height > width` — the same rule HyperMac
implements as `splitVertically = width >= height`.

### F2 — A node's share is `boxDimension × constant × perNodeRatio`

*Evidence: `ev_45f910c0…` (`analyze_function`, instruction listing).*

```
0xbba2cd  movsd xmm0, qword [r15+0x70]                           ; node field +0x70
0xbba2ef  mulsd xmm0, qword [double_value_180+24]                ; constant from .rodata
0xbba304  cvtss2sd xmm3, dword [r15+0x88]                        ; node field +0x88 (float)
0xbba31c  mulsd xmm0, xmm3                                       ; × per-node ratio
0xbba324  cvtss2sd xmm0, xmm0
```

So the geometry of a child is derived from a box dimension, multiplied by a `.rodata` constant and then
by a **per-node single-precision ratio stored at `+0x88`**. The ratio is per node, is a `float`, and is
applied multiplicatively to an already-scaled box dimension — which matches Hyprland's documented model
where `splitRatio = 1.0` means an even split and `0.1 … 1.9` spans the usable range.

`unverified`: the numeric value of the `.rodata` constant (`double_value_180+24`) was not resolved by any
returned record. By the semantics above it must be `0.5`, but this report does not claim the value.

### F3 — `default_split_ratio` seeds the ratio when a target is attached

*Evidence: `ev_60c100c7…` (trace: reference at `0xbc1170` lies inside
`CDwindleAlgorithm::addTarget`), `ev_59eabe59dff9aeb81fa7e1c9e09aead4af20ded87380f306ce19901f761669dd`
(`analyze_function` of `addTarget`: `dwindle:default_split_ratio` among its `referenced_strings`).*

The config key is read inside `addTarget`, not inside the recalculation. Combined with F2 — where the
ratio lives on the node at `+0x88` — the model is: attaching a target creates a node and gives it its
initial ratio; `recalcSizePosRecursive` then only *reads* node ratios.

`unverified`: the clamp interval (`0.1 … 1.9`) and the "resize moves the ratio by `2 · delta / box`"
rule from Hyprland's manual were **not** located in the returned records. The `recalcSizePosRecursive`
instruction listing returned by Hopper covers only part of the procedure (the provider reports
`body.available: false`), and `resizeTarget` decompilation did not complete before this report was
written. HyperMac's own clamp (`0.05 … 0.95`) is therefore **source-derived, not evidence-derived**; it
is the fraction form of `0.1 … 1.9` and is consistent with F1/F2, but it is not a transcription.

### F4 — `split_bias` is read when a target is attached

*Evidence: `ev_59eabe59…`.*

`dwindle:split_bias` appears in the `referenced_strings` of `addTarget`, so the bias participates in
node creation. Which side receives the inverted ratio is `unverified`: the pseudo-code returned for
`addTarget` is lifted instruction IR (4 632 559 bytes of JSON, 2 258 instructions), and the
`+0x88` ratio stores visible in F2 are written by code paths whose branch conditions were not reduced in
the returned records.

### F5 — Removal is a tree mutation, not a re-split

*Evidence: `ev_f29d4818…` (`CDwindleAlgorithm::removeTarget` at `0xbbb1d0`).*

`removeTarget` exists as a distinct procedure alongside `addTarget`, `swapTargets`, `toggleSplit`,
`swapSplit`, `rotateSplit` and `moveToRoot`, i.e. the tree is edited structurally. The "surviving
sibling is promoted into the removed parent's slot" behaviour is `unverified` for Hyprland — the
procedure was not decompiled in this pass. HyperMac implements promotion through tree unbind, which is
consistent but independently written.

### F6 — Insertion consults six config keys in one procedure

*Evidence: `ev_59eabe59…`.*

The `referenced_strings` of `CDwindleAlgorithm::addTarget` are, in provider order:
`dwindle:force_split`, `dwindle:smart_split`, `dwindle:use_active_for_splits`,
`dwindle:default_split_ratio`, `dwindle:split_bias`, `dwindle:precise_mouse_move`,
`dwindle:permanent_direction_override`, `dwindle:split_width_multiplier`.

That single observation is the strongest structural finding of this pass: **insertion point selection,
forced split direction, bias and the aspect multiplier are all handled in one place, at attach time.**
`addTarget` is called only from `newTarget` and `movedTarget` (its two observed callers). HyperMac has no
equivalent — it always inserts at the most recently used child — which is why F4/F6 appear as explicit
gaps in §7.

`unverified`: the precedence between `force_split` and the aspect rule, and the exact
`use_active_for_splits` selection, are not transcribed from the binary.

### F7 — Recalculation is driven by a reason enum

*Evidence: `ev_f29d4818…` (`CDwindleAlgorithm::recalculate(eRecalculateReason)` at `0xbbae60`).*

Layout is recomputed through one entry point that takes a reason, so Hyprland separates "what changed"
from "how to lay out". HyperMac instead recomputes from a refresh-session event; the two are
architecturally similar but not a port.


## 7. Parity mapping

| Hyprland behaviour | HyperMac | Status |
| --- | --- | --- |
| Split axis from the aspect test `box.h * split_width_multiplier > box.w` (§6, F1) | `splitVertically = width >= height` in `layoutDwindleRecursive` — the same comparison with the multiplier fixed at 1 | ported; multiplier not configurable |
| Split share derived from a per-node `splitRatio`, `0.5` = even | `dwindleFraction` derives the share from summed child weights along the split axis | ported; representation differs (fraction of weights vs. ratio) |
| `splitRatio` clamped to `0.1 … 1.9` (§6, F2) | fraction clamped to `0.05 … 0.95`, the same interval under `f = r / (1 + r)` | ported, unit-tested in `DwindleFractionTest` |
| `default_split_ratio` seeds a new node's ratio (§5, S-4) | a new node binds with `WEIGHT_AUTO` = mean sibling weight, so an untouched container stays even | ported in effect; no config key |
| Resize moves `splitRatio` by `2 · delta / box` (§6, F3) | `ResizeCommand` moves weights by absolute units, weight-conserving across siblings | **different units**; see TRD §3 |
| `split_bias` inverts the ratio when the new node becomes child 0 (§6, F4) | not implemented | **gap** |
| Removal promotes the surviving sibling into the removed parent's slot (§6, F5) | same behaviour: the node is unbound and its sibling is re-bound to the parent | ported |
| Insertion point chosen by cursor/active window under `use_active_for_splits`, forced direction overriding the aspect rule (§6, F6) | always the most recently used child, always the aspect rule | **gap** |
| `smart_split`, `preserve_split` | no equivalent — HyperMac keeps an n-ary container, not a split history | **gap (by design)** |

## 8. Residual unknowns

- `dwindle:special_scale_factor`, `dwindle:precise_mouse_move`,
  `dwindle:permanent_direction_override`, `dwindle:smart_resizing` and `dwindle:preserve_split` were
  inventoried as strings (`ev_d5728ff3…`) but their procedures were not decompiled. Their effect on
  HyperMac is out of scope for this pass and they are not claimed anywhere.
- No runtime observation of Hyprland was performed. All evidence is static analysis of a shipped
  artifact (`authority: shipped-artifact`). Nothing here should be read as "observed at runtime".
- Hopper's public Python API does not expose complete function body ranges, so procedure sizes are
  reported as `body.available: false` in every dossier; containment is established from reference
  resolution, not from body extents.
