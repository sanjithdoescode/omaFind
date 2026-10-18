# omaFind

Blazing-fast, Spotlight-style local file search and application launcher for [Omarchy Linux](https://omarchy.org/) and Hyprland. Press a key, find applications or any file across your system in milliseconds, and get right back to work.

> **One box, instant access.** Type your query, then:
>
> - **Enter** launches the selected application or opens the file in your default application.
> - **Ctrl+C** copies the absolute path to your clipboard.
> - **Ctrl+Enter** searches Google in your default browser if you need to search the web.

**Plugin ID:** `sanjith.omafind` · **License:** MIT · **Version:** 2.0.0 · **Author:** [Sanjith](https://github.com/sanjithdoescode)

---

## What's New in v2.0

- 🦀 **Native Rust Backend**: Rewritten from Python into a compiled, high-performance Rust engine (`omafind-search`) with Link-Time Optimization (LTO) for near-instant execution and low memory footprint.
- 🚀 **Application Launcher**: Search and launch installed desktop applications (`.desktop`) with rich application icon resolution and `gtk-launch` integration.
- 🎯 **Smart Hybrid Navigation**: Completely eliminated hover-conflict bugs. Arrow keys navigate and scroll without stationary cursor interference, while intentional mouse movements smoothly regain control with unified highlighting.

---

## Features

- 🚀 **Unified App Launcher & File Finder**:
  - Automatically indexes `.desktop` files across `/usr/share/applications` and `~/.local/share/applications`.
  - Matches on app name, exec binary, comments, keywords, and categories.
  - Prioritizes apps ahead of files, rendering high-resolution system icons via Omarchy's icon theme engine.
- ⚡ **Dual-Engine Search**:
  - **Index Mode (`plocate`)**: Instantaneous sub-10ms lookup against the system inverted index database.
  - **Live Mode (`fd`)**: Multi-threaded traversal directly on the filesystem (`Ctrl+L`) to locate new, unindexed files.
- 🎯 **Configurable Search Scope**:
  - Restricts search to `$HOME` (`~`) by default for speed and relevance.
  - Quick toggle with `Ctrl+H` to search the entire filesystem (`/`).
- ⌨️🖱️ **Seamless Keyboard & Mouse Modality**:
  - Full arrow-key (`↑`/`↓`) and `PageUp`/`PageDown` navigation.
  - Unified selection highlight — no dual-highlighting or stationary cursor conflicts when scrolling through results.
  - Moving the mouse by more than 2 pixels immediately hands control back to mouse selection.
  - `Enter` opens the item (or launches the app); `Tap`/click selects and opens immediately.
  - `Ctrl+C` copies the full path with animated toast confirmation.
  - `Ctrl+Enter` falls back to a web search in your browser.
  - `Esc` immediately dismisses the overlay.
- 📂 **Auto File Classification & Nerd Font Icons**:
  - Distinct icons for applications, directories, source code, images, video, audio, PDFs, archives, text documents, and configuration files.
- 🗂️ **Smart Path Formatting**:
  - Replaces `$HOME` with `~` for clean presentation.
  - Elides paths from the left (`ElideLeft`) so parent directories remain visible even in deeply nested folder structures.
- 🪟 **Liquid-Glass Design**:
  - Preserves the frosted pill + expandable card with soft sheen, border rim, and smooth animations.
  - Draggable search pill that remembers its screen position across sessions in `~/.local/state/omafind/position.json`.

---

## Requirements

omaFind relies on standard Linux utilities available on Arch Linux and Omarchy:

- **[`plocate`](https://gitlab.com/eile/plocate)** — Primary search backend (recommended for instant queries).
  - Ensure the updatedb timer is enabled:
    ```bash
    sudo systemctl enable --now plocate-updatedb.timer
    ```
- **[`fd`](https://github.com/sharkdp/fd)** — Fallback engine for live unindexed searches.
- **`wl-clipboard`** — Provides `wl-copy` for Wayland clipboard support.
- **`xdg-utils`** — Provides `xdg-open` to launch files in default applications.
- **`gtk-launch`** — Launches desktop applications cleanly.
- **[Nerd Fonts](https://www.nerdfonts.com/)** — Required for file-type icons in the result list (configured in your Omarchy font settings).
- **Rust / Cargo** *(optional)* — Only required if building the search binary from source. A pre-compiled release binary is included in `bin/`.

---

## Installation

### Via Omarchy Plugin Manager

Install directly with the Omarchy plugin manager:

```bash
omarchy plugin add https://github.com/sanjithdoescode/omaFind.git --enable --yes
```

### Manual / From Source

Clone the repository and compile the native Rust backend:

```bash
git clone https://github.com/sanjithdoescode/omaFind.git ~/.config/omarchy/plugins/sanjith.omafind
cd ~/.config/omarchy/plugins/sanjith.omafind
./install.sh
```

### Keybinding & Window Rules

Add the keybinding and Hyprland layer-shell blur rule to your `~/.config/hypr/bindings.lua`:

```lua
-- Bind omaFind toggle (e.g. ALT + SPACE or SUPER + SPACE)
o.bind("ALT + SPACE", "omaFind", "omarchy-shell shell toggle sanjith.omafind '{}'")

-- GPU-accelerated glass blur for the overlay namespace
hl.layer_rule({ match = { namespace = "^omafind$" }, blur = true, ignore_alpha = 0.45 })
```

> **Tip:** If you want the overlay pre-loaded into memory for instantaneous response on keypress, ensure `"sanjith.omafind"` is included in the `plugins` array of `~/.config/omarchy/shell.json`.

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
| **Typing** | Search Pill | Live debounced search against apps & filesystem |
| **`↑` / `↓`** | Results List | Navigate selection item-by-item |
| **`Page Up` / `Page Down`** | Results List | Jump selection by 10 items |
| **`Enter`** | Selected Result | Launch app (`gtk-launch`) or open file (`xdg-open`) |
| **`Click` / `Tap`** | Result Row | Select and immediately open target |
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
 │  • Modality-aware selection (keyboard vs. mouse tracking)   │
 │  • 120ms keystroke debounce timer                           │
 └───────────────────────────┬─────────────────────────────────┘
                             │
                  bin/omafind-search (Rust)
                             │
          ┌──────────────────┼──────────────────┐
          ▼                  ▼                  ▼
   [ Desktop Apps ]     [ plocate ]          [ fd ]
  .desktop parser    Primary file index    Live crawl
   Name, Exec, etc.     Fastest (~6ms)   Fallback (Ctrl+L)
          │                  │                  │
          └──────────────────┼──────────────────┘
                             │ Scored & Ranked JSON
                             ▼
 ┌─────────────────────────────────────────────────────────────┐
 │               SearchModel.js Helper                         │
 │  • JSON output validation and string length sanitization    │
 │  • Nerd Font & theme icon mapping per classified type       │
 │  • Path abbreviation (~/ replacement for $HOME)             │
 └───────────────────────────┬─────────────────────────────────┘
                             │
            ┌────────────────┼────────────────┐
            ▼                ▼                ▼
       [ Enter ]       [ Ctrl+Enter ]      [ Ctrl+C ]
  gtk-launch/xdg-open  Google Search       wl-copy
   (App / Default)   (Default Browser)   (Clipboard)
```

---

## Standalone Backend Testing

You can run and benchmark the backend binary directly from your terminal:

```bash
# Search for apps and files in $HOME
./bin/omafind-search --query "terminal" --limit 50

# Search with live multi-threaded fd crawling across the entire system
./bin/omafind-search --query "config" --all --live
```

---

## Credits & Acknowledgments

- Built by **[Sanjith](https://github.com/sanjithdoescode)**.
- Adapted from the glass overlay interface of **[omaSearch](https://github.com/5h3rd1l/omaSearch)** by Rubas Ali and **[omAsk](https://github.com/shabdar/omarchy-ask)** by Ali Shabdar.
- Built for **[Omarchy Linux](https://omarchy.org/)** and **[Quickshell](https://quickshell.outfoxxed.me/)**.

## License

This project is licensed under the [MIT License](LICENSE).
