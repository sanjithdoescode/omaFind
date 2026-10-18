#!/usr/bin/python3
"""omaFind local file search backend.

Prints a single JSON object on stdout, then exits.

  search.py --query <text> [--limit N] [--home-only] [--live]

  --query      The search string (required)
  --limit      Max results (default 50)
  --home-only  Restrict results to $HOME (default: on)
  --live       Use fd instead of plocate (finds newly created files
               not yet in the plocate index)

Output:
  {"ok": true,  "results": [{"path":"…","name":"…","dir":"…","kind":"…"}, …]}
  {"ok": false, "error": "…"}
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

HOME = os.path.expanduser("~")
MAX_RESULTS = 50
SEARCH_TIMEOUT = 5


# ---------------------------------------------------------------------------
# File classification
# ---------------------------------------------------------------------------

_CODE_EXTS = {
    ".py", ".js", ".mjs", ".ts", ".tsx", ".jsx", ".rs", ".go", ".c", ".cpp",
    ".h", ".hpp", ".java", ".kt", ".swift", ".rb", ".php", ".lua", ".sh",
    ".bash", ".zsh", ".fish", ".ps1", ".cs", ".dart", ".zig", ".ex", ".exs",
    ".clj", ".scala", ".r", ".m", ".pl", ".jl", ".vim", ".el", ".qml",
}
_IMAGE_EXTS = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".bmp", ".ico",
    ".tiff", ".tif", ".avif", ".heic", ".raw",
}
_VIDEO_EXTS = {".mp4", ".mkv", ".avi", ".mov", ".webm", ".flv", ".m4v", ".wmv"}
_AUDIO_EXTS = {".mp3", ".flac", ".ogg", ".wav", ".aac", ".opus", ".m4a", ".wma"}
_ARCHIVE_EXTS = {".zip", ".tar", ".gz", ".bz2", ".xz", ".7z", ".rar", ".zst"}
_DOC_EXTS = {".md", ".txt", ".rst", ".org", ".tex", ".rtf", ".adoc"}
_DATA_EXTS = {".json", ".yaml", ".yml", ".toml", ".xml", ".csv", ".tsv", ".ini", ".cfg", ".conf", ".env"}


def classify(path: str) -> str:
    """Return a kind string for icon selection in the UI."""
    if os.path.isdir(path):
        return "dir"
    ext = Path(path).suffix.lower()
    if ext in _CODE_EXTS:
        return "code"
    if ext in _IMAGE_EXTS:
        return "image"
    if ext in _VIDEO_EXTS:
        return "video"
    if ext in _AUDIO_EXTS:
        return "audio"
    if ext == ".pdf":
        return "pdf"
    if ext in _ARCHIVE_EXTS:
        return "archive"
    if ext in _DOC_EXTS:
        return "text"
    if ext in _DATA_EXTS:
        return "data"
    return "file"


# ---------------------------------------------------------------------------
# Result building
# ---------------------------------------------------------------------------

def build_results(paths: list[str]) -> list[dict]:
    """Convert raw paths to result dicts, abbreviating $HOME as ~."""
    out = []
    for p in paths:
        p = p.rstrip("\n")
        if not p:
            continue
        name = os.path.basename(p) or p
        directory = os.path.dirname(p)
        # Show ~ instead of /home/user for readability
        display_dir = ("~" + directory[len(HOME):]) if directory.startswith(HOME) else directory
        out.append({
            "path": p,
            "name": name,
            "dir": display_dir,
            "kind": classify(p),
        })
    return out


# ---------------------------------------------------------------------------
# Search backends
# ---------------------------------------------------------------------------

def search_plocate(query: str, limit: int, home_only: bool) -> list[dict]:
    """Search via plocate (index-based, ~6ms). Filters to $HOME if home_only."""
    if home_only:
        # plocate has no --root / --include-dir flag; request more results and
        # filter client-side.  4× gives good home coverage before the cap.
        fetch = min(limit * 6, 500)
        args = ["plocate", "-i", "-l", str(fetch), "--", query]
    else:
        args = ["plocate", "-i", "-l", str(limit), "--", query]

    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=SEARCH_TIMEOUT,
        )
    except (subprocess.TimeoutExpired, OSError) as exc:
        raise RuntimeError(f"plocate failed: {exc}") from exc

    paths = result.stdout.splitlines()
    if home_only:
        home_prefix = HOME + "/"
        paths = [p for p in paths if p.startswith(home_prefix) or p == HOME]
    paths = paths[:limit]
    return build_results(paths)


def search_fd(query: str, limit: int, home_only: bool) -> list[dict]:
    """Search via fd (live filesystem crawl, always up-to-date)."""
    base = HOME if home_only else "/"
    args = [
        "fd",
        "--ignore-case",
        "--max-results", str(limit),
        "--",
        query,
        base,
    ]
    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=SEARCH_TIMEOUT,
        )
    except (subprocess.TimeoutExpired, OSError) as exc:
        raise RuntimeError(f"fd failed: {exc}") from exc

    paths = result.stdout.splitlines()[:limit]
    return build_results(paths)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    args = sys.argv[1:]
    query = ""
    limit = MAX_RESULTS
    home_only = True   # default: search $HOME only
    live = False

    i = 0
    while i < len(args):
        a = args[i]
        if a == "--query" and i + 1 < len(args):
            query = args[i + 1]
            i += 2
        elif a == "--limit" and i + 1 < len(args):
            try:
                limit = max(1, min(200, int(args[i + 1])))
            except ValueError:
                pass
            i += 2
        elif a == "--home-only":
            home_only = True
            i += 1
        elif a == "--all":
            home_only = False
            i += 1
        elif a == "--live":
            live = True
            i += 1
        else:
            i += 1

    if not query or not query.strip():
        sys.stdout.write(json.dumps({"ok": False, "error": "No query provided"}) + "\n")
        sys.stdout.flush()
        sys.exit(1)

    try:
        use_fd = live or not shutil.which("plocate")
        if use_fd:
            results = search_fd(query, limit, home_only)
        else:
            results = search_plocate(query, limit, home_only)

        sys.stdout.write(json.dumps({"ok": True, "results": results}) + "\n")
        sys.stdout.flush()

    except Exception as exc:
        sys.stdout.write(json.dumps({"ok": False, "error": str(exc)}) + "\n")
        sys.stdout.flush()
        sys.exit(1)


if __name__ == "__main__":
    main()
