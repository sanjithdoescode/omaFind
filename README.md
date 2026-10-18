# omaFind

A blazing-fast, Spotlight-style local file search and application launcher for [Omarchy Linux](https://omarchy.org/) and Hyprland. Built with an interactive [Quickshell](https://quickshell.outfoxxed.me/) frosted-glass interface and powered by a compiled, native Rust search engine (`omafind-search`).

Press a key, search applications and files across your system with sub-millisecond responsiveness, and launch or copy paths instantly.

```
                  ┌─────────────────────────────────────────┐
                  │   Search files in ~…                 ~ │
                  └─────────────────────────────────────────┘
                  ┌─────────────────────────────────────────┐
                  │ 50 files                                │
                  │ 󰀻 Firefox Web Browser                   │
                  │   /usr/share/applications               │
                  │ 󰉋 Projects                              │
                  │   ~/Projects                            │
                  │ 󰈙 omaFind-local-search-plan.md          │
                  │   ~/.gemini/antigravity-cli/brain       │
                  └─────────────────────────────────────────┘
```

> **One keystroke, instant access:**
> - **Enter** launches the selected desktop application or opens the file in your default viewer.
> - **Ctrl+C** copies the target's absolute path directly to your Wayland clipboard.
> - **Ctrl+Enter** falls back to a Google search in your default web browser.

**Plugin ID:** `sanjith.omafind` · **License:** MIT · **Version:** 2.0.0 · **Author:** [Sanjith](https://github.com/sanjithdoescode)

---

## Key Capabilities

### 🦀 Compiled Native Rust Backend
- Completely rewritten from Python into an optimized native Rust binary (`omafind-search`) with Link-Time Optimization (LTO).
- Executes queries, desktop application indexing, ranking, and JSON serialization in single-digit milliseconds with minimal memory overhead.

### 🚀 Desktop Application Launcher
- Automatically scans and parses `.desktop` files across `/usr/share/applications` and `~/.local/share/applications`.
- Matches on app name, binary executable, descriptions, keywords, and categories with relevance scoring.
- Launches applications cleanly via `gtk-launch`, resolving desktop theme icons through Omarchy's icon theme engine.

### ⚡ Dual-Engine File Search
- **Index Mode (`plocate`)**: Instantaneous sub-10ms lookup against the local inverted index database.
- **Live Mode (`fd`)**: Multi-threaded real-time crawler (`Ctrl+L`) to discover newly created files not yet indexed by `plocate`.

### 🎯 Configurable Search Scope
- Restricts searches to `$HOME` (`~`) by default for speed, relevance, and noise reduction.
- Quick shortcut (`Ctrl+H`) instantly toggles search scope between `$HOME` and the entire filesystem root (`/`).

### 🪟 Fluid Glass UI & Clean Viewport Alignment
- Built on Omarchy's liquid-glass design system with frosted pill, soft sheen, dynamic compositor blur, and expandable results card.
- **Reliable Top Alignment**: Search results always start neatly at index 0 without clipping or unwanted initial downward offsets.
- **Pinned Viewport Controls**: Scrollbar and edge fade gradients remain stationary on the viewport frame as items scroll beneath them.
- **Position Persistence**: Draggable search pill remembers screen coordinates across sessions in `~/.local/state/omafind/position.json` via atomic Rust updates.

### ⌨️ Conflict-Free Hybrid Navigation
- Full keyboard navigation: `↑` / `↓` for item-by-item selection and `PageUp` / `PageDown` for 10-item jumps.
- Modality-aware pointer tracking: resting mouse cursors cannot hijack keyboard selection or introduce duplicate highlights; intentional mouse movement (>2px delta) smoothly reclaims selection.

---

## Requirements

Ensure the following tools are installed on your Omarchy/Arch system:

| Dependency | Purpose | Recommended Installation |
| :--- | :--- | :--- |
| **[`plocate`](https://gitlab.com/eile/plocate)** | High-speed primary file index | `sudo pacman -S plocate` |
| **[`fd`](https://github.com/sharkdp/fd)** | Fallback live file traversal | `sudo pacman -S fd` |
| **`wl-clipboard`** | Wayland clipboard support (`wl-copy`) | `sudo pacman -S wl-clipboard` |
| **`xdg-utils`** | Opening files in default applications (`xdg-open`) | `sudo pacman -S xdg-utils` |
| **`gtk-launch`** | Clean desktop application launching | Provided by `gtk3` / `gtk4` |
| **[Nerd Fonts](https://www.nerdfonts.com/)** | File classification glyphs | Configured in Omarchy theme settings |
| **Rust / Cargo** *(optional)* | Only needed if building backend from source | `sudo pacman -S rust` |

> [!TIP]
> Make sure `plocate-updatedb.timer` is enabled for regular index updates:
> ```bash
> sudo systemctl enable --now plocate-updatedb.timer
> ```

---

## Installation

### Via Omarchy Plugin Manager

Install and enable omaFind directly:

```bash
omarchy plugin add https://github.com/sanjithdoescode/omaFind.git --enable --yes
```

### From Source

Clone the repository and compile the native Rust backend:

```bash
git clone https://github.com/sanjithdoescode/omaFind.git ~/.config/omarchy/plugins/sanjith.omafind
cd ~/.config/omarchy/plugins/sanjith.omafind
./install.sh
```

### Hyprland Keybinding & Layer Rules

Add the shortcut and layer-shell compositor blur to `~/.config/hypr/bindings.lua`:

```lua
-- Toggle omaFind overlay with ALT + SPACE (or SUPER + SPACE)
o.bind("ALT + SPACE", "omaFind", "omarchy-shell shell toggle sanjith.omafind '{}'")

-- Compositor glass blur for the overlay namespace
hl.layer_rule({ match = { namespace = "^omafind$" }, blur = true, ignore_alpha = 0.45 })
```

Reload the shell to apply changes:

```bash
omarchy-shell shell reloadConfig
```

---

## Shortcuts & Controls

| Shortcut | Context | Action |
| :--- | :--- | :--- |
| **`Alt + Space`** | Global (Hyprland) | Toggle omaFind overlay |
| **Type text** | Search Pill | Live debounced search against applications & files |
| **`↑` / `↓`** | Results List | Navigate selection item-by-item |
| **`Page Up` / `Page Down`** | Results List | Jump selection by 10 items |
| **`Enter`** | Selected Result | Launch app (`gtk-launch`) or open file (`xdg-open`) |
| **`Click` / `Tap`** | Result Row | Select and immediately open target |
| **`Ctrl + C`** | Selected Result | Copy absolute path to clipboard (`wl-copy`) |
| **`Ctrl + Enter`** | Search Pill | Search query in default browser via Google |
| **`Ctrl + H`** | Search Pill | Toggle search scope between **`$HOME` (`~`)** and **Whole System (`/`)** |
| **`Ctrl + L`** | Search Pill | Toggle search backend between **Indexed (`plocate`)** and **Live (`fd`)** |
| **`Esc`** | Any | Dismiss overlay |

---

## Architecture

```
                       [ ALT + SPACE ]
                              │
                              ▼
  ┌─────────────────────────────────────────────────────────────┐
  │       Overlay.qml (Quickshell Layer-Shell Overlay)          │
  │  • Frosted glass pill + card with GlassSheen & border sheen │
  │  • Draggable pill with persistent screen coordinates        │
  │  • Viewport-pinned scrollbar and edge gradient fades        │
  │  • Modality-aware hybrid keyboard and mouse navigation      │
  │  • 120ms debounced search trigger                           │
  └───────────────────────────┬─────────────────────────────────┘
                              │
                   bin/omafind-search (Rust)
                              │
           ┌──────────────────┼──────────────────┐
           ▼                  ▼                  ▼
    [ Desktop Apps ]     [ plocate ]          [ fd ]
   .desktop scanner   Primary file index    Live crawl
    Name, Exec, etc.    Fastest (~2ms)    Fallback (Ctrl+L)
           │                  │                  │
           └──────────────────┼──────────────────┘
                              │ Scored & Ranked JSON (with icons & glyphs)
                              ▼
  ┌─────────────────────────────────────────────────────────────┐
  │                        Overlay.qml                          │
  │  • Synchronous ListModel population & index 0 alignment     │
  │  • Desktop theme icon resolution & Nerd Font file glyphs    │
  │  • Atomic position persistence via omafind-search --save-pos│
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

The search engine binary can be executed independently from the command line:

```bash
# Query applications and files in $HOME (default)
./bin/omafind-search --query "browser" --limit 50

# Live search across the entire filesystem
./bin/omafind-search --query "config" --all --live

# Persist drag coordinates via stdin
echo '{"dragX": 100, "dragY": 200}' | ./bin/omafind-search --save-pos
```

---

## Updating & Removing

```bash
# Update plugin to latest version
omarchy plugin update sanjith.omafind

# Remove plugin
omarchy plugin remove sanjith.omafind --yes
```

---

## Credits & Acknowledgments

- Built by **[Sanjith](https://github.com/sanjithdoescode)**.
- Interface styling inspired by **[omaSearch](https://github.com/5h3rd1l/omaSearch)** by Rubas Ali and **[omAsk](https://github.com/shabdar/omarchy-ask)** by Ali Shabdar.
- Built for **[Omarchy Linux](https://omarchy.org/)** and **[Quickshell](https://quickshell.outfoxxed.me/)**.

---

## License

This project is licensed under the [MIT License](LICENSE).
