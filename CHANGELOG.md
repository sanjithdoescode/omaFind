# Changelog

## 2.0.0 — omaFind

- **Native Rust Search Engine**: Replaced Python search script with compiled Rust binary (`omafind-search`) featuring LTO for sub-millisecond lookups.
- **Desktop Application Launcher**: Indexes `.desktop` files across `/usr/share/applications` and `~/.local/share/applications` with app name, binary, category, and keyword matching. Launches apps via `gtk-launch`.
- **Themed App Icons**: Resolves application icons from Omarchy's icon theme engine with Nerd Font glyph fallback.
- **Fixed Results Initial Viewport Offset**: Eliminated the scroll offset race condition where initial search results started ~52px down. Results now reliably start aligned at the top on index 0.
- **Hybrid Keyboard & Mouse Navigation**: Unifies selection highlighting; mouse hover only claims selection on intentional pointer movement (>2px delta), preventing stationary cursor interference when navigating via keyboard.
- **Pinned Viewport Scrollbar & Edge Fades**: Anchored the scrollbar and gradient fade overlays to the `Flickable` viewport frame so they remain stationary while content scrolls.
- **Atomic Position Persistence in Rust**: Pill drag coordinates persist atomically via `omafind-search --save-pos` to `~/.local/state/omafind/position.json`.

## 1.0.0 — omaFind

First release of **omaFind** (`sanjith.omafind`), an ultra-fast local file search overlay for Omarchy Linux and Hyprland, adapted from the glass interface of omaSearch.

- **Dual-Engine Search**: Powered by `plocate` for instant index search (~6ms) with an `fd` fallback / live search mode (`Ctrl+L`) for newly created files.
- **Scope Toggle**: Switch between `$HOME`-only search (`~`) and whole-system search (`/`) with `Ctrl+H`.
- **Keyboard-Driven Workflow**: Navigate results with `↑`/`↓` and `PageUp`/`PageDown`, open in default app with `Enter` (`xdg-open`), copy path to Wayland clipboard with `Ctrl+C` (`wl-copy`), search Google in browser with `Ctrl+Enter`.
- **Nerd Font Glyphs**: Auto file type classification with distinct Nerd Font icons for folders, code, images, audio, video, pdfs, archives, data, and docs.
- **Glass UI**: Retains Omarchy theme integration, liquid-glass sheen, compositor blur (`namespace: "omafind"`), draggable pill, and position persistence.
- **Zero AI / Zero Telemetry**: Fully local, runs on-device with no external network requests or background daemons.

---

## omaSearch Historical Releases


- Security: the overlay no longer writes its state files (`history.json`, `settings.json`, `position.json`) itself. Every write goes through `ask.py --save`, which checks the folder each time and writes relative to its verified descriptor (temp file with `O_EXCL | O_NOFOLLOW`, then rename), so a symlinked state folder can't redirect a write
- The state files are read only after `ask.py --prepare` has confirmed the folder is a real, private folder of yours; if it isn't, omaSearch saves nothing and says why

## 1.1.0

- Security: omaSearch's folders (`~/.local/state/omasearch`, `~/.cache/omasearch`) are created and made private without ever following a symlink (opened with `O_NOFOLLOW`, then `fchmod`), and folders you don't own are refused
- Security: settings and the model cache are written through a fresh temp file with a random name (`mkstemp`) and renamed into place, so a planted link can't redirect a write; pasted images get `mktemp` names
- Ctrl+I opens a temporary chat: nothing is saved (no recent-chats entry, title or question history), and Claude / Codex keep no session on disk. It has its own violet look, like a private window
- Shift+Enter adds a new line; the input grows with your text (up to about six lines, then scrolls), and line breaks are kept when you send

## 1.0.0 — omaSearch

First release as omaSearch, based on omAsk 1.0.5 by Ali Shabdar.

- Chat in the overlay: follow-ups continue the same session; Claude answers stream from a warm process
- Markdown answers with syntax-coloured code, a Copy button and clickable links
- Tool steps you can expand to see each command and its output
- Safe mode (on by default): Allow / Always in this chat / Deny before commands run
- Recent chats under the input, including older Claude chats; filter, keyboard, pins, clear; short titles for new chats
- Paste images (Ctrl+V) or pick one from clipboard history for Claude
- Select to copy; click to copy a message or code block
- Short / Detailed answers, model and agent menus, Ctrl+Up / Down question history
- Liquid-glass look, toast confirmations, Ctrl+H help

## omAsk (before the rename)

### 1.0.5

Open in browser was leaving Chromium on about:blank.

- `wl-copy` / `wtype` / `hyprctl` inherit `WAYLAND_DISPLAY` (and the Hyprland session vars)
- The continuation packet still never appears on argv

### 1.0.4

Fix blank Open in browser composers.

- Keep the continuation packet off Chromium argv (`about:blank`, then paste the encoded URL)
- Flush overlay stdin before closing it so the JSON handoff is not truncated
- If Chromium reuses a window, still paste into it

### 1.0.3

Open in browser continues from the overlay exchange.

- Seeds a continuation packet (`I asked` / `You answered (desktop overlay)`) as `?q=`
- Confirms Send so the web chat is already running
- Prompt and overlay answer travel on stdin JSON, not argv

### 1.0.2

Keep user prompts off process command lines.

- Overlay writes the question to `ask.py --ask` on stdin (`Process.write`)
- `wl-copy` and `open_chat.py` take clipboard/prompt bytes on stdin
- Agent CLIs receive the question via stdin or `--prompt-file /dev/stdin`, not `-p` / positional argv
- Copilot and OpenCode overlay answers fail closed to Open in browser (those CLIs require the prompt as an argument)
- Browser handoff launches the chat host without `?q=` on Chromium argv, then pastes the seeded URL
- Notifications no longer include the question text

### 1.0.1

Marketplace-ready identity.

- Plugin id `io.github.shabdar.omask` (the `omarchy.*` namespace is reserved for built-ins)
- Display name `omAsk`
- Docs: install path, IPC, update/remove commands, external dependencies
- Install still does not write Hyprland binds or other user config
- Migration: `omarchy plugin remove omask --yes`, re-add from git, then update the Super+Q bind to toggle `io.github.shabdar.omask`

### 1.0.0

First public release.

- Plugin id `omask` (the `omarchy.*` namespace is reserved for built-ins)
- Centered overlay for a one-shot question to `omarchy default agent`
- Short on-screen answer via that agent's CLI (Grok, Claude, Gemini, Copilot, Codex, OpenCode, Crush, Pi, Oh My Pi)
- Open in browser starts the agent's web chat with `?q=` in a new Chromium window; grok.com Send is confirmed
