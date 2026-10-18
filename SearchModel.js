.pragma library

// omaFind – SearchModel.js
// Shared helpers for the search overlay. No AI, no markdown, no chat history.

// ─── File-type icons (Nerd Font glyphs) ────────────────────────────────────
// Requires a Nerd Font to be set as the terminal/UI font in your theme.
var KIND_ICONS = {
  app:     "󰀻",
  dir:     "󰉋",
  code:    "󰈮",
  image:   "󰈟",
  video:   "󰎁",
  audio:   "󰎈",
  pdf:     "󰈦",
  archive: "󰛫",
  text:    "󰈙",
  data:    "󰈙",
  file:    "󰈔"
}

function iconFor(kind) {
  return KIND_ICONS[String(kind)] || KIND_ICONS.file
}

// ─── String helpers ─────────────────────────────────────────────────────────

function clip(value, limit) {
  var text = String(value || "")
  if (text.length <= limit) return text
  return text.slice(0, limit) + "…"
}

function escapeHtml(text) {
  return String(text || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
}

// ─── JSON output parser ─────────────────────────────────────────────────────

function parseSearchOutput(raw) {
  var text = String(raw || "").trim()
  if (!text) return { ok: false, error: "No response from search helper.", results: [] }

  // Find the JSON object in the output
  var start = text.indexOf("{")
  var end   = text.lastIndexOf("}")
  if (start === -1 || end === -1 || end <= start)
    return { ok: false, error: clip(text, 200), results: [] }

  var data
  try {
    data = JSON.parse(text.slice(start, end + 1))
  } catch (e) {
    return { ok: false, error: "Could not parse helper output.", results: [] }
  }
  if (!data || typeof data !== "object")
    return { ok: false, error: "Invalid helper output.", results: [] }

  var results = []
  if (Array.isArray(data.results)) {
    for (var i = 0; i < data.results.length && i < 200; i++) {
      var r = data.results[i]
      if (!r || typeof r !== "object") continue
      results.push({
        path: clip(String(r.path || ""), 1000),
        name: clip(String(r.name || ""), 200),
        dir:  clip(String(r.dir  || ""), 300),
        kind: clip(String(r.kind || "file"), 20),
        icon: clip(String(r.icon || ""), 200)
      })
    }
  }

  return {
    ok:      data.ok === true,
    error:   clip(String(data.error || ""), 200),
    results: results
  }
}
