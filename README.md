# omaFind

Blazing-fast, Spotlight-style local file search overlay for [Omarchy Linux](https://omarchy.org/) and Hyprland. Press a key, find any file across your system in milliseconds, and keep working.

> **One box, instant results.** Type your search query, then:
>
> - **Enter** opens the selected file or folder in your default application.
> - **Ctrl+C** copies the absolute path to your clipboard.
> - **Ctrl+Enter** searches Google in your default browser if you can't find it locally.

**Plugin id:** `sanjith.omafind` · **License:** MIT · **Version:** 1.0.0 · **Author:** [Sanjith](https://github.com/sanjithdoescode)

---

## Overview

**omaFind** is a native Quickshell layer-shell overlay for Omarchy. It repurposes the frosted liquid-glass pill and card aesthetic of the open-source `omaSearch` AI plugin, eliminating external API calls and background LLM daemons in favor of an ultra-responsive, fully local file search engine powered by `plocate` and `fd`.

- **Instant search as you type**: Average query lookup time is **~6ms** using `plocate`'s memory-mapped inverted index.
- **Live filesystem fallback**: Toggle to `fd` with `Ctrl+L` for real-time crawling to discover brand new files created after the last database index update.
- **Native look & feel**: Fully adapts to your active Omarchy theme palette (`Color.menu` and `Style`) with hardware-accelerated compositor blur and glass sheen.
- **100% Private & Offline**: Zero network requests, zero telemetry, zero background daemons.

---

## Features

- ⚡ **Dual-Engine Search**:
  - **Index Mode (`plocate`)**: Instantaneous sub-10ms lookup against the system inverted index database.
  - **Live Mode (`fd`)**: Multi-threaded traversal directly on the filesystem (`Ctrl+L`) to locate new, unindexed files.
- 🎯 **Configurable Search Scope**:
  - Restricts search to `$HOME` (`~`) by default for speed and relevance.
  - Quick toggle with `Ctrl+H` to search the entire filesystem (`/`).
- ⌨️ **Keyboard-Driven Workflow**:
  - Full arrow-key (`↑`/`↓`) and `PageUp`/`PageDown` navigation.
  - `Enter` opens the item with `xdg-open`.
  - `Ctrl+C` copies the full path with animated toast confirmation.
  - `Ctrl+Enter` falls back to a web search in your browser.
  - `Esc` immediately dismisses the overlay.
- 📂 **Auto File Classification & Nerd Font Icons**:
  - Clean icons distinguishing directories, source code, images, video, audio, PDFs, archives, text documents, and config/data files.
- 🗂️ **Smart Path Formatting**:
  - Replaces `$HOME` with `~` for cleaner presentation.
  - Elides paths from the left (`ElideLeft`) so parent directories remain visible even in deeply nested folder structures.
- 🪟 **Liquid-Glass Design**:
  - Preserves the frosted pill + expandable card with soft sheen, border rim, and smooth animations.
  - Draggable search pill that remembers its screen position across sessions in `~/.local/state/omafind/position.json`.

---

## Requirements

omaFind uses standard Linux tools available on Arch / Omarchy:

- **[`plocate`](https://gitlab.com/eile/plocate)** — Primary search backend (recommended for instant queries).
  - Ensure the updatedb timer is enabled:
    ```bash
    sudo systemctl enable --now plocate-updatedb.timer
    ```
- **[`fd`](https://github.com/sharkdp/fd)** — Fallback engine for live unindexed searches.
- **`wl-clipboard`** — Provides `wl-copy` for Wayland clipboard support.
- **`xdg-utils`** — Provides `xdg-open` to launch files in default applications.
- **[Nerd Fonts](https://www.nerdfonts.com/)** — Required for file-type icons in the result list (configured in your Omarchy font settings).

---

## Installation

Install directly with the Omarchy plugin manager:

```bash
omarchy plugin add https://github.com/sanjithdoescode/omaFind.git --enable --yes
```

### Keybinding & Window Rules

Add the keybinding and Hyprland layer-shell blur rule to your `~/.config/hypr/bindings.lua`:

```lua
-- Bind omaFind toggle (e.g. ALT + SPACE or SUPER + SPACE)
o.bind("ALT + SPACE", "omaFind", "omarchy-shell shell toggle sanjith.omafind '{}'")

-- GPU-accelerated glass blur for the overlay namespace
hl.layer_rule({ match = { namespace = "^omafind$" }, blur = true, ignore_alpha = 0.45 })
```

> **Note:** If you want the overlay pre-loaded into memory for instantaneous response on keypress, ensure `"sanjith.omafind"` is included in the `plugins` array of `~/.config/omarchy/shell.json`.

### Updating & Removing

```bash
# Update plugin to latest version
omarchy plugin update sanjith.omafind

# Remove plugin
omarchy plugin remove sanjith.omafind --yes
```

---

## Shortcuts & Navigation

| Key | Context | Action |
| :--- | :--- | :--- |
| **`Alt + Space`** | Global (Hyprland) | Toggle omaFind overlay |
| **Typing** | Search Pill | Live debounced search against filesystem |
| **`↑` / `↓`** | Results List | Navigate selection item-by-item |
| **`Page Up` / `Page Down`** | Results List | Jump selection by 10 items |
| **`Enter`** | Selected Result | Open file or folder in default application (`xdg-open`) |
| **`Ctrl + C`** | Selected Result | Copy full absolute path to clipboard (`wl-copy`) |
| **`Ctrl + Enter`** | Search Pill | Search query on Google in default browser |
| **`Ctrl + H`** | Search Pill | Toggle search scope between **`$HOME` (`~`)** and **Whole System (`/`)** |
| **`Ctrl + L`** | Search Pill | Toggle backend between **Indexed (`plocate`)** and **Live (`fd`)** |
| **`Esc`** | Any | Close / dismiss the overlay |

---

## Architecture

```
                      [ ALT + SPACE ]
                             │
                             ▼
 ┌─────────────────────────────────────────────────────────────┐
 │       Overlay.qml (Quickshell Layer-Shell Overlay)          │
 │  • Frosted glass pill + card with GlassSheen & border sheen │
 │  • Draggable pill with remembered screen coordinates        │
 │  • 120ms keystroke debounce timer                           │
 └───────────────────────────┬─────────────────────────────────┘
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
                             │ JSON output
                             ▼
 ┌─────────────────────────────────────────────────────────────┐
 │               SearchModel.js Helper                         │
 │  • JSON output validation and string length sanitization    │
 │  • Nerd Font icon mapping per classified file / MIME type   │
 │  • Path abbreviation (~/ replacement for $HOME)             │
 └───────────────────────────┬─────────────────────────────────┘
                             │
            ┌────────────────┼────────────────┐
            ▼                ▼                ▼
      [ Enter ]       [ Ctrl+Enter ]      [ Ctrl+C ]
       xdg-open       Google Search       wl-copy
     (Default App)    (Default Browser)  (Clipboard)
```

---

## Standalone Backend Testing

You can run and benchmark the backend script directly from your terminal:

```bash
# Fast plocate index search in $HOME
python3 search.py --query "README" --limit 50

# Live multi-threaded fd search across the entire system
python3 search.py --query "config" --all --live
```

---

## Credits & Acknowledgments

- Built by **[Sanjith](https://github.com/sanjithdoescode)**.
- Adapted from the glass overlay interface of **[omaSearch](https://github.com/5h3rd1l/omaSearch)** by Rubas Ali and **[omAsk](https://github.com/shabdar/omarchy-ask)** by Ali Shabdar.
- Built for **[Omarchy Linux](https://omarchy.org/)** and **[Quickshell](https://quickshell.outfoxxed.me/)**.

## License

This project is licensed under the [MIT License](LICENSE).
