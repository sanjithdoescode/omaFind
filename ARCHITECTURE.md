# Architecture

omaFind is a `keepLoaded` Omarchy overlay (plugin id `sanjith.omafind`). The shell summons `Overlay.qml`, which executes the Python search backend (`search.py`) and paints the results.

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
                         python3 -I -S search.py
                                    │
                      ┌─────────────┴─────────────┐
                      ▼                           ▼
               [ plocate ]                    [ fd ]
            Primary (~6ms)              Fallback / Live
         Inverted index database     Live multi-threaded crawl
         Filter to $HOME / all       Finds unindexed/new files
                      │                           │
                      └─────────────┬─────────────┘
                                    │ JSON Array on stdout
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         SearchModel.js Helper                           │
│  • JSON output validation and normalization                             │
│  • Nerd Font icon mapping per classified file/directory type            │
│  • Path abbreviation (~/ replacement for $HOME)                         │
└───────────────────────────────────┬─────────────────────────────────────┘
                                    │
                   ┌────────────────┼────────────────┐
                   ▼                ▼                ▼
             [ Enter ]       [ Ctrl+Enter ]      [ Ctrl+C ]
              xdg-open       Google Search       wl-copy
            (Default App)    (Default Browser)  (Clipboard)
```

## Overlay.qml

The UI and all state. `open` / `close` / `toggle` / `dismiss` form the IPC surface.

| Component | What it does |
| --- | --- |
| `searchProc` | Subprocess running `search.py --query <text> [--limit 50] [--home-only/--all] [--live]` |
| `resultsModel` | `ListModel` storing results (`rPath`, `rName`, `rDir`, `rKind`) |
| `resultsList` | `Flickable` view rendering matching files with Nerd Font icons, selection highlight, and left-elided paths |
| `copyProc` | Puts the selected item's absolute path onto the Wayland clipboard via `/usr/bin/wl-copy` |
| `savePosProc` | Atomic write of pill drag coordinates to `~/.local/state/omafind/position.json` |
| `GlassSheen` | Liquid-glass finish (sheen, rim, and gradient) on the card and pill |

State lives in `~/.local/state/omafind/position.json`.

## SearchModel.js

Shared helper library (`.pragma library`):
- `KIND_ICONS`: Nerd Font icon mapping for directory, code, image, video, audio, pdf, archive, text, data, and generic files.
- `parseSearchOutput`: Validates and parses the JSON response from `search.py`, clipping string lengths to safeguard UI memory.
- `clip` & `escapeHtml`: String utilities for sanitizing labels.

## search.py

Standalone search CLI script. Executes either `plocate` (default index) or `fd` (live traversal) and prints a structured JSON object to stdout.

- `--query <text>`: Search term (required).
- `--limit <int>`: Max results to return (default 50).
- `--home-only` / `--all`: Filter results to `$HOME` (default) or entire filesystem.
- `--live`: Force `fd` search to discover files not yet indexed by `plocate`.

## Theme

Colors are bound directly to `Color.menu` and `Style` from Omarchy's design system (`qs.Commons`, `qs.Ui`). No colors are hard-coded.
