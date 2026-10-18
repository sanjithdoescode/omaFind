// src/main.rs – omafind-search entry point.
//
// Merges app results and file results, sorts by score, deduplicates by path,
// caps at --limit, attaches Nerd Font glyphs, and emits a single-line JSON object.

mod args;
mod apps;
mod files;
mod save_pos;
mod score;

use serde::Serialize;
use std::collections::HashSet;

// ---------------------------------------------------------------------------
// Output types
// ---------------------------------------------------------------------------

#[derive(Serialize)]
struct ResultItem {
    path: String,
    name: String,
    dir: String,
    kind: String,
    glyph: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    icon: Option<String>,
}

#[derive(Serialize)]
struct Output {
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
    results: Vec<ResultItem>,
}

// Internal: result + its ranking score (not emitted to JSON).
struct Ranked {
    item: ResultItem,
    score: f32,
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn emit_error(msg: &str) {
    let out = Output {
        ok: false,
        error: Some(msg.to_string()),
        results: vec![],
    };
    println!("{}", serde_json::to_string(&out).unwrap_or_default());
}

pub fn kind_glyph(kind: &str) -> &'static str {
    match kind {
        "app" => "󰀻",
        "dir" => "󰉋",
        "code" => "󰈮",
        "image" => "󰈟",
        "video" => "󰎁",
        "audio" => "󰎈",
        "pdf" => "󰈦",
        "archive" => "󰛫",
        "text" => "󰈙",
        "data" => "󰈙",
        _ => "󰈔",
    }
}

fn clip_str(s: &str, limit: usize) -> String {
    if s.chars().count() <= limit {
        s.to_string()
    } else {
        let mut out: String = s.chars().take(limit).collect();
        out.push('…');
        out
    }
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

fn main() {
    let cfg = args::parse();

    if cfg.save_pos {
        save_pos::run();
        return;
    }

    if cfg.query.trim().is_empty() {
        emit_error("No query provided");
        std::process::exit(1);
    }

    let mut ranked: Vec<Ranked> = Vec::new();

    // 1. App results (already carry a +0.5 kind bonus → float above file hits).
    for r in apps::search(&cfg.query) {
        let glyph = kind_glyph(&r.kind);
        ranked.push(Ranked {
            score: r.score,
            item: ResultItem {
                glyph,
                path: clip_str(&r.path, 1000),
                name: clip_str(&r.name, 200),
                dir: clip_str(&r.dir, 300),
                kind: clip_str(&r.kind, 20),
                icon: if r.icon.is_empty() {
                    None
                } else {
                    Some(clip_str(&r.icon, 200))
                },
            },
        });
    }

    // 2. File results (plocate or fd, noise-filtered, scored).
    for r in files::search(&cfg) {
        let glyph = kind_glyph(&r.kind);
        ranked.push(Ranked {
            score: r.score,
            item: ResultItem {
                glyph,
                path: clip_str(&r.path, 1000),
                name: clip_str(&r.name, 200),
                dir: clip_str(&r.dir, 300),
                kind: clip_str(&r.kind, 20),
                icon: None,
            },
        });
    }

    // Sort descending by score.
    ranked.sort_by(|a, b| {
        b.score
            .partial_cmp(&a.score)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    // Dedup by path, then take the top N.
    let mut seen: HashSet<String> = HashSet::new();
    let results: Vec<ResultItem> = ranked
        .into_iter()
        .filter(|r| seen.insert(r.item.path.clone()))
        .take(cfg.limit)
        .map(|r| r.item)
        .collect();

    let out = Output {
        ok: true,
        error: None,
        results,
    };
    println!(
        "{}",
        serde_json::to_string(&out).unwrap_or_else(|_| {
            r#"{"ok":false,"error":"Serialization failed","results":[]}"#.to_string()
        })
    );
}
