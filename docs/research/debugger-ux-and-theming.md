# Debugger UX and Neovim-native theming research

Research date: **2026-11-07**. Repository snapshot: `1ea565148d5e91e7e248c41e93b96a81f510924e`, isolated branch `t3/48964544`.

## Decision proposed

Keep the plugin's compact, section-based Neovim interface. Retain semantic highlight links and user-owned layouts. Improve the distinction between **keyboard focus, the row being browsed, the inspected frame, the execution stop, changed values, and errors**, with text or shape cues as well as color. Prefer a few independently configurable roles over a new palette or a second UI framework.

Everything recommended below is a **proposal for later consideration**, not an approved implementation plan or a stabilization requirement. Stabilization has since merged into `main` as `7305f27`; this report retains its inspected pre-merge snapshot. The independent maintenance epic `dv-8x5` already contains seven recommendations; reconcile these findings with those tickets before creating any additional work. No source changes, environment changes, debugger/editor access, or Beads writes were performed for this research.

## Method and limits

This is an independent, selective investigation, not an exhaustive market audit or a ranking. Internet search was followed by reading official documentation, repositories, selected source files, and GitHub's public repository/commit API. Comparator selection favors direct relevance to terminal interaction, Neovim conventions, or a distinct advanced debugging workflow. Popularity was not the selection criterion.

The local implementation was inspected read-only. “Already present” means supported by this snapshot's source, not visually or behaviorally retested here. No apps were launched and no screenshots were taken. Documentation pages can advance independently of installed versions: the current GDB manual is a development manual, and the retrieved CLion help identifies itself as 2026.3. Neovim's current help was cross-checked against its supported 0.11 baseline and 0.12 API documentation where version differences matter. Links to moving documentation describe the retrieval date, not a permanent version guarantee.

Impeccable's **Operate** guidance informed the analysis: familiarity, scanability, consistency, and task density outrank visual expression. Its web-specific typography, skeleton, and motion advice is not automatically applicable to a terminal editor. No product brief or design document was initialized.

## Selected comparators

Activity dates below are the most recent default-branch commit observed through the public API, linked to that exact commit. A recent commit is a maintenance signal, not evidence of responsiveness or implementation quality. In particular, a copyright or README edit is weaker evidence than a substantive fix.

| Comparator | Selection and maintenance evidence | Documented interaction worth studying | Transfer boundary |
| --- | --- | --- | --- |
| **GDB TUI** | Maintained debugger baseline; the official [release schedule](https://www.sourceware.org/gdb/schedule/) records GDB 18.1 on 2026-09-25. | [Overview](https://sourceware.org/gdb/current/onlinedocs/gdb.html/TUI-Overview.html): execution marker, explicit breakpoint markers, changed registers, focus/status line. [Commands](https://sourceware.org/gdb/current/onlinedocs/gdb.html/TUI-Commands.html): explicit focus and configurable layouts. | Borrow state clarity and keyboard operation; do not adopt its window system inside Neovim. |
| **CGDB** | Terminal/vi comparator; [commit 2026-10-06](https://github.com/cgdb/cgdb/commit/ae240a2fb828fb3e8d57bd75f603a93e28d3fff1). | [Official manual source](https://github.com/cgdb/cgdb/blob/ae240a2fb828fb3e8d57bd75f603a93e28d3fff1/doc/cgdb.texi): separate source/command focus, regex search, and distinct executing-line versus selected-line displays. | Strongest precedent for separating browsing from execution; its specific colors are not portable defaults. |
| **GDB dashboard** | Maintained, command-first terminal interface; [commit 2026-07-17](https://github.com/cyrus-and/gdb-dashboard/commit/7b9b1260a8b3e9dd57b6cbf302bdfba71cec4014), a copyright update. | [README](https://github.com/cyrus-and/gdb-dashboard#readme): modular state appears when the inferior stops; existing GDB commands remain available. | Borrow compact summaries and the command escape hatch. This is not a full interactive tree/window TUI. |
| **NND** | Modern native TUI comparator; [commit/release 2026-07-09](https://github.com/al13n321/nnd/commit/93731d2ce014394e8259f86976851754e344296e). Its [README](https://github.com/al13n321/nnd#readme) explicitly says it is **not in active feature development**, but receives bug fixes/small requests. | Documentation makes responsiveness, asynchronous/cancellable expensive work, and progress feedback explicit goals. | Useful maintained reference, not an actively expanding platform: Linux/x86-64/native code, no REPL, remote protocol, DAP, or reverse execution. SSH use is not remote-debugger support. |
| **nvim-dap widgets** | Closest dependency-level comparator; [commit 2026-09-11](https://github.com/mfussenegger/nvim-dap/commit/cfa2d58f4537aca6ca83e2de1a0d9f1491121264). | [Widget help](https://github.com/mfussenegger/nvim-dap/blob/cfa2d58f4537aca6ca83e2de1a0d9f1491121264/doc/dap.txt): sidebar/float/preview builders, expandable entries and an action menu. | Native interaction vocabulary is more relevant than IDE chrome. Its widget API is documented as experimental. |
| **nvim-dap-ui** | Direct multi-pane Neovim comparator; [commit 2026-07-14](https://github.com/rcarriga/nvim-dap-ui/commit/cc9dd33aade7f20bae414d0cba163bc60d4d4b43), a styling change. | [README](https://github.com/rcarriga/nvim-dap-ui#readme): elements grouped in layouts, temporary floating elements, repeated evaluation can enter an existing float, and element-specific actions. | Borrow consistent local actions and inspect-then-enter behavior; simultaneous panes are an option, not a target layout. |
| **nvim-gdb** | Useful non-DAP Neovim control; [commit 2026-06-15](https://github.com/sakhnik/nvim-gdb/commit/67abac716b626ece57f3a7c72121542f0b3edfe9). | [README](https://github.com/sakhnik/nvim-gdb#readme): thin CLI integration, command watch windows, backtrace/breakpoint location lists; documents avoiding single-letter mappings in terminal input. | Borrow native lists/source navigation and respect for the debugger CLI; backend features such as rr are not automatically dap-view features. |
| **VS Code** | Current cross-language, DAP-oriented GUI reference. | [Debugging guide](https://code.visualstudio.com/docs/debugtest/debugging): selected-frame data context, active-session execution actions, conditional breakpoints/hit counts/logpoints. [Theme reference](https://code.visualstudio.com/api/references/theme-color): separate roles for top frame, focused frame, changed values, state labels, and value types. | Borrow semantic distinctions and context; translate menus into commands/local help rather than recreating a sidebar-heavy desktop. |
| **JetBrains CLion** | Current native-code IDE reference, directly relevant to large structs and threads. | [Tool window](https://www.jetbrains.com/help/clion/debug-tool-window.html): session tabs and configurable pane grouping. [Suspended-program guide](https://www.jetbrains.com/help/clion/examining-suspended-program.html): frame/thread inspection, hidden library frames, watch errors, inline changes, non-modal evaluation. | Borrow progressive disclosure and clear context. IDE-specific evaluators and backend/thread-control features are not generic DAP promises. |
| **Visual Studio** | Current advanced concurrency and inspection reference. | [Parallel Stacks](https://learn.microsoft.com/en-us/visualstudio/debugger/using-the-parallel-stacks-window): thread/task views, search/filtering, and distinct execution versus inspection frames. [Tabular visualizer](https://learn.microsoft.com/en-us/visualstudio/debugger/view-data-in-tabular-visualizer): dedicated inspection of supported collections. | Borrow searchable context and focused inspection. Graph canvases and rich collection visualizers are beyond this plugin's present scope. |
| **Chrome DevTools** | Current language-specific GUI reference for stepping and reducing stack noise. | [JavaScript debugging reference](https://developer.chrome.com/docs/devtools/javascript/reference): scope/console inspection, stepping, async stack inspection, and ignore-listed scripts. | Borrow navigation and reversible noise reduction. Filtering displayed frames is not equivalent to changing which code the debugger steps through. |

**Secondary modal reference, with caution:** [debugmaster.nvim](https://github.com/MironPascalCaseFan/debugmaster.nvim#readme) provides a dedicated debug mode, help, and panel/float switching. Its [latest observed commit](https://github.com/MironPascalCaseFan/debugmaster.nvim/commit/505d9a269d657ce8e0fa5601e0530f0d8798038c) is 2026-01-02, a README correction; the README warns about breaking changes. This is useful design evidence, but insufficient evidence to call it currently active development. The transferable idea is short commands in an explicitly entered mode; imposing that mode globally would be a separate product decision.

The strongest complementary references are therefore **CGDB for browsing/execution separation; nvim-dap widgets for native affordances; nvim-dap-ui for contextual actions; VS Code for session/capability semantics; CLion for data inspection; and GDB TUI for noncolor status**. The other projects test the boundaries rather than supply a feature checklist.

**GUI-to-terminal transfer proposal:** translate context menus into local commands/help, visualizers into explicit inspection views, and pane selection into ordinary Neovim windows/sections. Preserve the operation and its context, not the pixels. Do not import floating toolbars, hover-only hit targets, drag-only reordering, decorative cards, animated value flashes, web fonts, or motion timings. Dense text, stable rows, native search and reversible disclosure are the appropriate medium here.

## What this fork already does

Paths below are relative to this report and refer to the snapshot above. They intentionally cover the fork's host and decoder extensions as well as upstream-style sections.

| Surface | Already present in source | Gap or qualification, not an implementation request |
| --- | --- | --- |
| Overall density | One active section, optional controls, configurable section list and split sizes; cursorline, no line numbers, no wrapping in the main view. [Configuration](../../lua/dap-view/config.lua), [view options](../../lua/dap-view/views/options.lua). | Sessions and console are available but omitted from the default section list. Narrow-width tab/control presentation needs a separate assessment. |
| Scopes | Lazy child traversal, retained expansion, changed-value detection, configurable sorting, scope collapse, generation-fenced publishing. [Scopes renderer](../../lua/dap-view/scopes/view.lua). | Expensive scopes are intentionally excluded by the renderer. Do not describe them as an accidental empty-data failure or promise all scopes are visible. |
| Deep/large values | Cell-based value truncation, configurable width/ellipsis, indent folds, scopes rerooting with breadcrumbs and root-up. `K` opens the retained full value. [Truncation](../../lua/dap-view/util/truncate.lua), [tree modules](../../lua/dap-view/tree/reroot.lua), [full-value preview](../../lua/dap-view/tree/value.lua). | “Full” means the complete value the plugin received; it cannot recover an adapter-truncated string. Generic child pagination is not implemented by these tree renderers. |
| Watches | Add/insert/edit/delete, expand, copy, set value, full-value preview; `vim.ui.input` prompts. [Keymaps](../../lua/dap-view/watches/keymaps.lua), [actions](../../lua/dap-view/watches/actions.lua), [evaluation](../../lua/dap-view/watches/eval.lua). | Context identity and unavailable/stale values deserve a clearer visible contract, especially across frame/session changes. |
| Hover | Expandable expression view, parent navigation, explicit edit action, quit and lifecycle cleanup; generation/request checks reject obsolete replies. [Hover](../../lua/dap-view/hover/init.lua), [evaluation](../../lua/dap-view/hover/eval.lua). | When hover evaluation is not supported, the current default context falls back to `repl`. A future UX decision should make that distinction understandable, rather than imply all hover evaluations are equivalent. |
| Mutation and decoder previews | Original variables can be edited through supported adapter requests. Negative parent references reject edits to raw/decoded preview nodes. Decoders expose `raw`, `decoded`, loading/error data, bounded async work, raw fallback, profile switching and context invalidation. [Set-value dispatch](../../lua/dap-view/views/set.lua), [decoder implementation](../../lua/dap-view/decoders/init.lua), [decoder contract](../value-decoders.md). | Read-only is enforced, but preview identity/editability should also be readable before attempting an edit. Do not equate a nonmodifiable buffer with side-effect-free target evaluation. |
| Breakpoints/exceptions | Breakpoint location/source display, jump/delete, copied source highlighting/sign extmarks; exception filters can be toggled. [Breakpoint renderer](../../lua/dap-view/breakpoints/view.lua), [actions](../../lua/dap-view/breakpoints/actions.lua), [exceptions](../../lua/dap-view/exceptions/keymaps.lua). | The list does not surface conditions/hit counts/log messages or offer an edit/toggle workflow. [Known limitations](../src/routes/known-issues/+page.md) record the upstream API constraints. Source inspection, not that possibly older page alone, establishes the current gap. |
| Threads/frames | Stopped-thread cue, current-frame highlight, subtle-frame visibility, pattern/inverse filtering, frame selection and configurable/forced jumps. [Thread renderer](../../lua/dap-view/threads/view.lua), [keymaps](../../lua/dap-view/threads/keymaps.lua), [actions](../../lua/dap-view/threads/actions.lua). | A current-frame highlight is an inspection-context marker, not proof it is the execution frame. Display filtering must not be sold as step filtering. |
| Sessions | Parent/child hierarchy, active-session highlight and explicit switching. [Session renderer](../../lua/dap-view/sessions/view.lua), [actions](../../lua/dap-view/sessions/actions.lua). | Active selection uses the same `FrameCurrent` role as frames; explicit session state text would be a proposal. DAP sessions differ from saved Vim sessions. |
| REPL/output | Reuses nvim-dap's REPL; separate terminal/console handling and per-session console navigation; autoscroll stops when browsing away from the bottom. [REPL](../../lua/dap-view/repl/init.lua), [console scroll](../../lua/dap-view/console/scroll.lua), [console keymaps](../../lua/dap-view/console/keymaps.lua). | Preserve the distinction between evaluation, adapter output, and inferior terminal I/O. Detached-viewer parity for REPL/terminal interaction is not established by this research. |
| Split/tab hosts | Split restoration is guarded by exact layout identity. Dedicated tabs have code/full layouts, optional frame following and termination close policy. [Split host](../../lua/dap-view/host/split.lua), [layout restoration](../../lua/dap-view/util/layout.lua), [tab host](../../lua/dap-view/host/tab.lua). | Tab `follow_frame=true` actively focuses the owned code window before stop handling. “Preserves the original layout” does not mean “never changes focus.” |
| Detached host | Owner-rendered text/extmarks, forwarded actions, overlays, highlight mirroring on attachment, viewer-loss fallback. Ordinary render flushes preserve the viewer cursor except on section changes. [Remote host](../../lua/dap-view/host/remote.lua), [viewer](../../lua/dap-view/host/viewer.lua). | Here `remote` means a detached UI viewer, not a new remote-debugger protocol. Theme mirroring and terminal capability policy have review points below. |
| Discovery/navigation | Section-letter hints; `]v`/`[v`, first/last navigation and counts; `g?` help; local mappings and descriptions; `switchbuf` and force-jump selection. [Base maps](../../lua/dap-view/base/keymaps.lua), [map helper](../../lua/dap-view/views/keymaps/util.lua), [help](../../lua/dap-view/views/keymaps/help.lua), [window selection](../../lua/dap-view/views/windows/init.lua). | Help is a hard-coded **Default Keymaps** document rather than a rendering of effective user mappings. Custom keys and newer tree commands can diverge from it. |

### Theming review points in the current snapshot

The main implementation is already close to a native policy: [highlight.lua](../../lua/dap-view/highlight.lua) creates prefixed groups with `default=true` links and runs the same definitions after `ColorScheme`. Value types inherit standard syntax groups; tab states inherit `TabLine*`; errors inherit diagnostics. [util/hl.lua](../../lua/dap-view/util/hl.lua) separately owns extmark placement and type mapping. This is a foundation to preserve.

The following are source-level observations, **not runtime reproductions or merge blockers**:

1. `FrameCurrent` and `WatchUpdated` both link to `DiagnosticVirtualTextWarn`. Inspected context, changed data and warnings are consequently conflated by default. Exception-filter disabled state links to `DiagnosticError`, although “disabled” is not necessarily an error.
2. `MissingData`, terminate and disconnect depend on `DapBreakpoint`. That is a dependency-owned group, not a built-in Neovim semantic guarantee. `FileName`/`LineNumber` depend on `qfFileName`/`qfLineNr`, which are established by the [quickfix syntax runtime](https://github.com/neovim/neovim/blob/v0.11.5/runtime/syntax/qf.vim), not guaranteed by the core highlight list alone. `TabSelectedSeparator` links to unprefixed `TabSelected`; verify whether the intended target was `NvimDapViewTabSelected`.
3. The 0.12-only dim/update calls omit `default=true`, unlike the base links. Therefore this file does not establish that **all** user attributes survive initialization and every scheme reload. This needs a focused override-preservation check before changing the mechanism, not a blanket claim that current links are broken.
4. Detached attachment sends resolved global highlight attributes and `background`; ordinary buffer flushes do not resend that bundle. No `ColorScheme`/`OptionSet` synchronization hook was found in the inspected host modules. The viewer explicitly sets `termguicolors=true`. A viewer already attached during a theme change, a 256-color terminal, or an owner using window-local highlight overrides requires explicit coverage. [Remote highlight collection/attachment](../../lua/dap-view/host/remote.lua), [viewer initialization](../../lua/dap-view/host/viewer.lua).

## Proposed Neovim-native styling policy

### Contract and lifecycle

**Proposal:** support any colorscheme by inheriting its semantic groups, preserving user overrides and retaining noncolor cues. Do not promise identical hues or measurable contrast under every arbitrary scheme. A scheme may deliberately give several roles the same attributes or leave a group empty.

Neovim's API documents `default` as non-overriding, `link` as taking precedence over accompanying attributes, and namespace activation separately from defining groups. The 0.11 API replaces a definition; 0.12 documents `update` and `dim`. These differences justify retaining the 0.11-compatible link path and version-gating enhancements. [Current API help](https://neovim.io/doc/user/api/#nvim_set_hl()), [0.11 API](https://github.com/neovim/neovim/blob/v0.11.5/runtime/doc/api.txt), [0.12 API](https://github.com/neovim/neovim/blob/v0.12.0/runtime/doc/api.txt).

Proposed rules:

- Define the public `NvimDapView*` role names once on load and restore missing defaults after `ColorScheme`. Keep defaults idempotent and avoid force-overwriting user definitions.
- Use live links, not RGB values copied from the current scheme. Avoid resolving and caching colors in the owner merely to synthesize lighter/darker variants.
- Document a user's `ColorScheme` callback for persistent explicit customizations. `default=true` prevents plugin replacement of an existing definition; it does not prevent the colorscheme itself from clearing it. Neovim documents both link/default behavior and `:highlight clear`. [Highlight linking/defaults](https://neovim.io/doc/user/syntax/#%3Ahi-default).
- `ColorScheme` runs after scheme loading. `background` changes can reload an active scheme; without one, default groups change. A future transport refresh may also need `OptionSet background` and capability changes, without recursive option writes. No plugin-owned dark/light palette is required. [Autocommand lifecycle](https://neovim.io/doc/user/autocmd/#ColorScheme), [option semantics](https://neovim.io/doc/user/options/#%27background%27).
- Treat a user's explicit highlight updates as authoritative. Do not attach heavy color polling to cursor movement. If detached mirroring is refreshed, do it at a clear theme/attachment boundary and keep `mirror_highlights=false` meaningful.

### Suggested role mapping, not approved default changes

These are candidate **links**, not colors. The standard syntax/UI roles are documented in [Neovim's highlight help](https://neovim.io/doc/user/syntax/#highlight-groups); diagnostic roles are documented in the [diagnostic framework](https://neovim.io/doc/user/diagnostic/#diagnostic-highlights). The extra text cues are proposals.

| Meaning | Candidate native role | Scope and noncolor cue |
| --- | --- | --- |
| Main/idle surface | `Normal`, `NormalNC`; floats `NormalFloat`/`FloatBorder` | Keep normal source/editor contrast; identify the active view by its title. |
| Section tabs | `TabLine`, `TabLineSel`, `TabLineFill` | Preserve existing mappings; label or bracket the selected section when space permits. |
| Cursor/browsed row | Native `CursorLine` | Cursor position means where the next local action applies. It must not silently select a debugger frame. |
| Inspected frame/session | Prefixed role linked to `QuickFixLine` | Mark the selected debugger context, for example `*`; keep it distinguishable when the cursor moves away. Its exact visual strength is a preference. |
| Execution stop | Existing nvim-dap stop sign; a separate prefixed stopped-state role linked to `DiagnosticWarn` | `>`/`stopped`, thread identity, and stop reason. A breakpoint stop is not an error. |
| Changed value | `NvimDapViewWatchUpdated` linked to `Changed` | Apply only to the value; add a compact changed marker. `Changed` exists in the [0.11 syntax vocabulary](https://github.com/neovim/neovim/blob/v0.11.5/runtime/doc/syntax.txt). `DiffText` is an optional stronger alternative, not a requirement. |
| Expression/name/type values | `Identifier`, `String`, `Number`, `Float`, `Boolean`, `Function`, `Constant` | Retain existing type mapping; unknown types remain readable normal text. Do not infer truth/success from green or false/error from red. |
| Actual failure/rejection | `DiagnosticError` | Include the adapter/decoder error text; color alone cannot identify the failure. |
| Pending/unavailable/stale/disabled | `Comment` or `NonText` for metadata | Write `loading`, `not available`, `stale`, or `disabled` explicitly; keep the main value legible. Disabled is not an error. |
| Filename/location | `Directory` and `LineNr`, or existing qf links with guaranteed runtime fallback | Keep line/column and enough path to disambiguate duplicate basenames. |
| Truncation/preview metadata | `Comment`; `Normal` for the actual preview | Explicit ellipsis/full-value action and `raw`/`decoded · read-only` identity. Read-only data need not be dimmed. |
| Controls | One neutral action role, inactive metadata role; error role only for failure | Discoverable text descriptions. Avoid coloring every step icon differently simply because the API exposes separate groups. |

`QuickFixLine` and `Changed` are semantic proposals rather than universally ideal appearances. Some schemes make quickfix selection vivid or diff text subtle. Keep role overrides independent; settle the defaults only after a bounded comparison across representative schemes.

### Namespaces, terminal colors and accessibility

**Proposal:** retain global, prefixed default links for public customization. Keep the existing extmark namespace for ownership/clearing. An extmark namespace does **not** require activating a private highlight namespace. A window highlight namespace is a different facility: it falls back to namespace 0 for missing definitions and takes precedence over `winhighlight`. Use it only if a specific host needs isolation, not as a general theming rewrite. [Window highlight namespace API](https://neovim.io/doc/user/api/#nvim_win_set_hl_ns()).

**Proposal:** do not set the user's `background`, colorscheme, fonts, or `termguicolors` to make the plugin look correct. Neovim uses GUI attributes for RGB terminal rendering and cterm attributes otherwise. Follow the terminal's capabilities and the user's choice. A detached viewer may live in a different terminal, so blindly forcing the owner's RGB mode is not a complete compatibility policy. If resolved attributes must cross the viewer boundary, retain RGB **and** cterm attributes where supplied and preserve the viewer's capability choice. [Terminal color option](https://neovim.io/doc/user/options/#%27termguicolors%27).

**Proposal:** use color redundantly. Test focus/selection/current-stop/changed/error cues in monochrome and with common color deficiencies in mind. Avoid low-contrast dimming for the only copy of a value, and avoid relying on italic/undercurl/blink. Neovim's own theme guidance specifies dark/light suitability, contrast targets and noncolor emphasis; these are useful validation goals, not a warrant to impose its palette on arbitrary user schemes. [Official theme guidelines](https://neovim.io/doc/user/dev_theme/).

**Proposal:** keep debugger signs independent from diagnostic sign definitions. Reuse `Diagnostic*` highlight roles where appropriate, but never redefine `DiagnosticSignError` glyphs or diagnostic priorities globally. Preserve nvim-dap sign customization. It already distinguishes breakpoint, conditional breakpoint, logpoint, stopped, and rejected states. [nvim-dap sign help](https://github.com/mfussenegger/nvim-dap/blob/cfa2d58f4537aca6ca83e2de1a0d9f1491121264/doc/dap.txt).

**Proposal:** offer an explicit ASCII icon preset, not unreliable automatic Nerd Font detection. Examples: tree `>`/`v`, stopped `>`, breakpoint `B`, conditional `C`, logpoint `L`, rejected `!`, enabled `[x]`, disabled `[ ]`; full words for controls in help. Signs must occupy one or two display cells, so the three-character checkbox belongs in list text, not a sign definition. Neovim specifies that restriction in [sign help](https://neovim.io/doc/user/sign/#%3Asign-define). Unicode/ASCII choice is taste; visible, distinct state and correct cell width are invariants.

## Proposed workflow and navigation policy

### Distinguish context from focus

Maintain these independent meanings:

| Context | Meaning | Proposed behavior |
| --- | --- | --- |
| Keyboard focus | Window receiving input | Ordinary background refresh does not move it. |
| Cursor row | Candidate for a local action | `j`/`k` browse; explicit activation selects a frame/session. |
| Inspected session/thread/frame | Context for locals, watches and REPL evaluation | Show identity where ambiguity matters; update dependent views atomically. |
| Execution location | Where a stopped thread actually paused | Keep a separate marker even when an older frame is inspected. |
| Last successful values | Snapshot from a particular suspended context | Never imply they are live while running or while a new context is loading. |

This separation is supported by [CGDB's distinct selection/execution displays](https://github.com/cgdb/cgdb/blob/ae240a2fb828fb3e8d57bd75f603a93e28d3fff1/doc/cgdb.texi), [Visual Studio's frame markers](https://learn.microsoft.com/en-us/visualstudio/debugger/using-the-parallel-stacks-window), and [VS Code's distinct frame theme roles](https://code.visualstudio.com/api/references/theme-color). It does not require their colors or full layouts.

**Execution controls proposal.** Make continue/pause, step over/into/out, terminate and disconnect findable by command and keyboard; keep the optional control bar optional. Derive availability from both session state and capabilities, including reverse stepping. Distinguish terminate from disconnect in action descriptions. A gray icon with a still-active callback is not sufficient availability feedback. Current [control callbacks](../../lua/dap-view/options/controls/base.lua) delegate to nvim-dap; no execution-key rebinding is needed merely to improve descriptions.

**Source navigation proposal.** Explicit frame/breakpoint selection may navigate source according to `switchbuf`. Passive refresh should preserve the user's source window, cursor and view; following a stop is a separate policy. Keep force-jump and a route back to the execution frame. Honor intentional tab frame-following rather than silently redefining it. Respect `winfixbuf` and do not steal REPL or terminal input windows. Current [source-jump utilities](../../lua/dap-view/views/util.lua) and [window-selection helpers](../../lua/dap-view/views/windows/switchbuf.lua) are existing seams to preserve.

**Layout proposal.** Keep split/tab/detached hosts as presentation choices over the same owner state. Do not restore a saved split layout after the user changes its topology; the existing identity guard already expresses that principle. Do not make closing a pane equivalent to killing the debug session: CLion's documented close-tab behavior is deliberately not a requirement to copy. Establish stop-focus policy explicitly, including adapter `preserveFocusHint`, rather than promising that every stop is nonintrusive.

### Trees, values, hover and editing

**Proposal:** preserve a stable compact row order: indentation/disclosure, name, optional metadata, value. Align within the visible region when helpful, without letting a long name push every value offscreen. Keep ordinary tree navigation and search usable; show reroot breadcrumbs and a visible root-up escape. Rerooting changes the view, not the adapter data or edit destination.

**Proposal:** distinguish three different limits: the UI abbreviated a value, the adapter returned an abbreviated value, or only some children were fetched. Show `more`/range/count only when supported by real data. Offer bounded, explicit child paging for large collections as a separate enhancement. The decoder's verified byte extraction in pages of 256 is **not** generic variable-tree pagination. Preserve already fetched expansion when possible, but invalidate obsolete adapter references across resume/context changes.

**Proposal:** keep `K` as a full retained-value preview, with wrapping/scrolling, copy, and clear exit. Do not auto-evaluate to “complete” a raw value. Raw and decoded children remain inspectable, labelled, and read-only; edits target the original adapter variable through an explicit prompt. Preserve raw data and a visible decode error when transformation fails. A local formatting rule and a target-executing evaluator must not share an indistinguishable safety label.

**Proposal:** an expression hover should initially inspect without unexpectedly capturing typing; explicit re-entry can focus an existing view. A value-edit prompt should identify the expression and relevant frame/session, support cancellation and preserve entered text on failure where feasible. Refresh after acceptance, not while a prompt is open. Current mutation dispatch already refreshes after successful replies and fences later context changes; preserve that work.

The protocol defines suspended-state lifetimes for variable references, paging, context-sensitive evaluation, optional mutation/reverse-step capabilities, and a focus-preservation hint. It also distinguishes debug-session termination from process exit. These are real capability/state boundaries, not appearance preferences. [Official DAP schema](https://github.com/microsoft/debug-adapter-protocol/blob/main/debugAdapterProtocol.json). Automatic arbitrary evaluation, live polling and memory reading are not implied by a wish for better previews.

### Breakpoints, REPL and output

**Breakpoint proposal:** show type and enabled/verified/rejected status before adding more colors. When the API reliably exposes them, offer concise condition/hit-count/log-message summaries with a focused full-details/edit action. Keep conditional breakpoints and logpoints distinct; a logpoint does not normally stop execution. Do not infer support from the existence of a GUI comparator. nvim-dap already accepts condition, hit-condition and log-message arguments; this plugin's list lacks that management surface. [nvim-dap breakpoint API](https://github.com/mfussenegger/nvim-dap/blob/cfa2d58f4537aca6ca83e2de1a0d9f1491121264/doc/dap.txt), [VS Code breakpoint workflow](https://code.visualstudio.com/docs/debugtest/debugging).

**REPL/output proposal:** retain nvim-dap's evaluator and completion behavior, keep target I/O separate, and show the relevant session/context. Preserve scrollback and the user's reading position; resume tail-following explicitly or at the bottom. Report command errors locally and preserve ordinary terminal typing. Do not duplicate a REPL evaluator or route output to a novel web-style notification stream. Existing console scrolling already implements much of the reading-position policy.

### State and failure contract

The table is a **proposed visible vocabulary**, not a request to build a new global state machine. Some mechanisms already exist, as noted above.

| State | Minimal readable representation | Interaction contract proposed |
| --- | --- | --- |
| No session | `No active session` plus the relevant command/help route | No fake empty variable tree. Preserve watch expressions. |
| Starting/loading | `Starting…` or `Loading <scope/frame/decoder>…` | Keep input responsive; show an error/timeout with a retry route. No progress percentage without a denominator. |
| Running | `Running`; previous inspection explicitly `stale` if retained | No accidental edits or expansion through references from the prior stop. |
| Stopped | `Stopped: <reason>` and selected session/thread | Allow inspection; distinguish the actual stopped frame from an inspected caller. |
| Context changing | New identity and pending data | Do not publish late results from an old frame/session. Keep cursor/expansion stable when identity permits. |
| Unavailable | `Not available in this frame` or adapter reason | Do not equate out-of-scope with zero, empty string, decode failure, or a disconnected adapter. |
| Error | Error text close to the affected node/action | Preserve raw data and unrelated views; retry is local when possible. |
| Exited/terminated/disconnected | State plus exit code/reason when known | Preserve useful output under the configured close policy. Never invent a process exit from a session-termination event. |
| Detached viewer lost | Explicit fallback/disconnection notice | Preserve owner session state and make the resulting host understandable. Current remote host already has fallback notification. |

NND's [documented responsiveness goals](https://github.com/al13n321/nnd#readme) support nonblocking expensive work; GDB TUI's [explicit status line](https://sourceware.org/gdb/current/onlinedocs/gdb.html/TUI-Overview.html) supports textual state. The exact wording and whether to retain stale values are product preferences, not facts mandated by those projects.

### Keyboard, narrow terminals and accessibility

**Proposal:** keep single-letter actions buffer-local and preserve normal Vim navigation/search/window commands. Global execution mappings should remain user-owned; nvim-dap intentionally configures none by default to avoid conflicts. An optional debug mode would need explicit entry/exit, an unmistakable mode indicator, and restoration of prior mappings. It is not required for this plugin. [nvim-dap mappings policy](https://github.com/mfussenegger/nvim-dap/blob/cfa2d58f4537aca6ca83e2de1a0d9f1491121264/doc/dap.txt), [debugmaster's explicit modal approach](https://github.com/MironPascalCaseFan/debugmaster.nvim#readme).

**Proposal:** generate discoverability from effective actions/mappings: section-local help, command names, disabled reasons, configured keys and mouse equivalents. Preserve `g?`; do not introduce mandatory which-key or fuzzy-finder dependencies. Do not give `h`/`l`, `s`, `d`, `c`, `K` or terminal Escape new global meanings. Existing buffer-local shadowing inside a debugger view is different from changing source editing.

**Proposal:** at narrow widths, retain the active section, state and help route; collapse optional control labels/secondary metadata before the value name or location. Do not silently enable wrap for all tree rows: it breaks one-row/action associations. Full-value floats, rerooting and horizontal navigation are existing escape routes. Use display-cell measurements for multibyte labels/icons. Clamp help/hover dimensions to available space and ensure they can scroll. Keyboard-only access must cover every action that has a click target.

**Proposal:** provide useful text in buffers/messages for users who cannot distinguish colors or icons. Do not claim screen-reader accessibility from keyboard support alone; terminal/Neovim/frontend behavior needs user testing. Keep raw control characters escaped in previews and make copy semantics explicit for escaped binary data.

## Core invariants versus preferences and product expansion

| Category | Items | Decision consequence |
| --- | --- | --- |
| **Core correctness/usability invariants** | Correct context identity; no obsolete async publication; raw fallback; preview mutation protection; truthful capability/state labels; no passive cursor stealing; preserve user-owned windows and custom highlights; usable keyboard and noncolor state cues. | Preserve during stabilization and any later UI work. Existing implementation of several invariants is recorded above; this report adds no release gate. |
| **Taste/default choices** | Exact semantic fallback for changed/selected rows; optional borders; icons versus ASCII default; location of controls; stale values retained versus cleared; how much metadata fits a row. | Compare a bounded set and decide explicitly. No fixed palette or universal pane layout follows from this research. |
| **Speculative product proposals** | Dedicated modal command layer, persistent pinned hover, collection table view, multi-thread comparison or stack grouping. | Separate opt-in product decisions; no implied implementation authorization. |
| **Deferred adapter/backend capabilities** | Generic paging, data/function/instruction breakpoints, reverse execution, memory/disassembly tools, live watches, async task graphs, step-into-target selection. | Evaluate only for a concrete use case and adapter support. Do not expand this research into “implement all DAP.” |

Disassembly already has an [optional custom-view integration](../src/routes/disassembly/+page.md); that is different from a built-in memory/register/debugger engine. Saved [Vim-session restoration](../../lua/dap-view/vim-sessions.lua) is also different from restoring a live process or DAP session. CLion's [live watches](https://www.jetbrains.com/help/clion/live-watches.html) demonstrate a specialized sampling workflow, not a justification for automatically evaluating every watch while the target runs.

## Candidate future work packages

These are **proposals**, not tickets created here. All implementation follows stabilization and the parent's adoption decision. Check `dv-8x5` first; merge overlapping acceptance criteria rather than duplicating its seven existing recommendations. The package boundaries below are intentionally narrow and do not propose a broad code refactor.

| Priority/package | Deliverable and meaningful acceptance | Dependencies / parallelism / conflicts |
| --- | --- | --- |
| **P1 — Theme contract** | Confirm default-link/override behavior on 0.11 and 0.12; resolve semantic alias review points; document the public roles and customization lifecycle. Validate two contrasting themes, built-in/default and minimal styling, dark/light reload, and explicit overrides. | Can be investigated alongside discovery docs. Conflicts in `highlight.lua`/`util/hl.lua`; assign one owner when future highlight work is approved. |
| **P1 — Visible context/state contract** | Separate browsing, inspected frame and execution stop; define running/stale/loading/error text and capability availability. Verify resume, session/frame switch, late replies, unsupported actions and termination. | Agree on roles with theme package first. Touches renderers/listeners/control descriptions; overlaps stabilization hot paths, so wait for them to settle. |
| **P1 — Effective keymap discovery** | Help reflects configured keys/actions and includes reroot/root-up, full values, host commands and read-only restrictions. All mouse actions have a keyboard route; test a remapped configuration and narrow help. | Mostly independent of theme work. Conflicts with keymap/help/command-definition changes; no new input framework dependency. |
| **P2 — Detached theme parity** | Verify initial/reload theme parity, `background` and RGB/cterm behavior, mirror opt-out and viewer loss; account for window-local highlight overrides or explicitly document the limitation. | Depends on theme contract. Own remote/viewer transport files separately; avoid concurrent host stabilization edits. Use isolated fixtures later, not the user's running editor. |
| **P2 — Large/read-only value inspection** | Clear raw/decoded/read-only/loading/error labels; truthful truncation/full-value behavior; width/height bounds and a usable reroot escape. Decide whether generic child paging is wanted before implementing it. | Theme roles first; can proceed independently of keymap work after agreeing action names. Shared scopes/watches/hover/decoder files are conflict hotspots; one coordinated workstream. |
| **P2 — Breakpoint detail workflow** | Capability-aware display/edit of condition, hit count and log message using a supported upstream API; distinguish disabled/rejected/logpoint. Validate the exact supported adapter contract. | Gated on API evidence, not on visual polish. Independent from host/theme work; avoid vendoring a second breakpoint state store merely for this screen. |
| **P3 — Focus/layout and compact-mode acceptance** | Record the chosen stop-focus policy; cover split/tab/detached, user-resized layouts, source folds, REPL/terminal typing, keyboard-only use and ASCII at narrow widths. | Acceptance can be specified independently; implementation overlaps host/state packages. Consolidate checks with existing tests rather than add a second test infrastructure. |

The validation dimensions are bounded proposals: minimum supported Neovim and a current release; dark/light and a sparse scheme; RGB/256-color plus a monochrome cue check; split/tab/detached; stopped/running/context switch/error; narrow/wide; default/remapped keys; Unicode/ASCII. This is not a demand for a full Cartesian-product matrix. Select representative combinations and test the boundaries that a given change affects.

## Preferences still worth deciding later

No unanswered preference blocks stabilization or this report. Before adopting UI changes, the material questions are:

1. Should a stop bring the dedicated debug tab to the foreground, preserve the currently focused view, or follow an explicit per-host preference? The current tab default follows the frame.
2. Should running views retain clearly labelled stale values or clear them? Either is coherent; an unlabeled old value is not.
3. Should changed data use a modest `Changed` foreground, stronger `DiffText`, or mainly a text marker? Keep the role configurable regardless.
4. Should ASCII be an easy documented preset or the default? Do not infer installed fonts from the current icons.
5. Is generic variable paging or breakpoint management actually a desired product investment after the existing maintenance epic? Comparator feature lists alone do not establish that priority.

## Evidence and handoff

Primary links are placed next to the claims they support. Repository activity was checked through `https://api.github.com/repos/<owner>/<repo>/commits?per_page=1` and repository metadata, then pinned commit links were recorded above. Official source was fetched directly when a rendered page was incomplete. No forum posts, third-party rankings or remembered product behavior support the technical recommendations.

Validation on the research date: all 40 distinct external link targets returned successful HTTP responses in a GET check (Microsoft Learn adds its version query); local source-link paths were checked. Source claims were checked against the retrieved documentation/code. This is link/source verification, not a runtime or visual test of any debugger.

Only this report is intended for adoption. It supplies rationale and candidate acceptance criteria; it does not authorize UI work, alter the current maintenance epic, or block the parent merge. In particular, the existing host, decoder and stabilization mechanisms should be carried forward, not rewritten to resemble a GUI debugger.
