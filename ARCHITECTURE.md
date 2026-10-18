# Architecture

omaFind is a `keepLoaded` Omarchy overlay (plugin id `sanjith.omafind`). The shell summons `Overlay.qml`, which executes the native Rust search backend (`bin/omafind-search`) and paints the results.

```
                      [ ALT + SPACE ] / omarchy-shell toggle
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│              Overlay.qml (Quickshell Layer-Shell Overlay)               │
│  • Frosted glass pill + card with GlassSheen and border sheen           │
│  • WlrLayershell namespace: "omafind" (compositor blur)                 │
│  • Draggable pill with remembered screen coordinates (position.json)    │
│  • Keystroke debouncing (searchDebounce)                                │
└───────────────────────────────────┬─────────────────────────────────────┘
                                    │
                         bin/omafind-search (Rust)
                                    │
               ┌────────────────────┼────────────────────┐
               ▼                    ▼                    ▼
        [ Desktop Apps ]       [ plocate ]            [ fd ]
       .desktop scanner      Primary (~6ms)       Fallback / Live
       Name, Exec, etc.     Inverted index DB    Multi-threaded crawl
               │                    │                    │
               └────────────────────┼────────────────────┘
                                    │ Scored, Ranked & Pre-sanitized JSON
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                              Overlay.qml                                │
│  • Direct JSON parsing into results ListModel                           │
│  • Nerd Font glyph & desktop theme icon rendering                       │
│  • Drag coordinate persistence via omafind-search --save-pos (Rust)     │
└───────────────────────────────────┬─────────────────────────────────────┘
                                    │
                   ┌────────────────┼────────────────┐
                   ▼                ▼                ▼
             [ Enter ]       [ Ctrl+Enter ]      [ Ctrl+C ]
          gtk-launch/open    Google Search       wl-copy
           (Default App)    (Default Browser)  (Clipboard)
```

## Overlay.qml

The UI and all state. `open` / `close` / `toggle` / `dismiss` form the IPC surface.

| Component | What it does |
| --- | --- |
| `searchProc` | Subprocess running `bin/omafind-search --query <text> [--limit 50] [--home-only/--all] [--live]` |
| `resultsModel` | `ListModel` storing results (`rPath`, `rName`, `rDir`, `rKind`, `rGlyph`, `rIcon`) |
| `resultsList` | `Flickable` view rendering matching apps and files with Nerd Font icons, selection highlight, and left-elided paths |
| `copyProc` | Puts the selected item's absolute path onto the Wayland clipboard via `/usr/bin/wl-copy` |
| `savePosProc` | Atomic write of pill drag coordinates via `bin/omafind-search --save-pos` to `~/.local/state/omafind/position.json` |
| `GlassSheen` | Liquid-glass finish (sheen, rim, and gradient) on the card and pill |

State lives in `~/.local/state/omafind/position.json`.

## omafind-search (Rust)

Standalone native Rust backend binary (`src/main.rs`). Scans desktop applications, queries `plocate` (default index) or `fd` (live traversal), scores/ranks hits, sanitizes output, and emits structured JSON to stdout. Also handles atomic position state persistence via `--save-pos`.

- `--query <text>`: Search term (required for search).
- `--limit <int>`: Max results to return (default 50).
- `--home-only` / `--all`: Filter results to `$HOME` (default) or entire filesystem.
- `--live`: Force `fd` search to discover files not yet indexed by `plocate`.
- `--save-pos`: Read `{dragX, dragY}` from stdin and atomically write to `position.json`.

## Theme

Colors are bound directly to `Color.menu` and `Style` from Omarchy's design system (`qs.Commons`, `qs.Ui`). No colors are hard-coded.
