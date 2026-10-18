// src/main.rs – omafind-search entry point.
//
// Merges app results and file results, sorts by score, deduplicates by path,
// caps at --limit, and emits a single-line JSON object to stdout that is
// wire-compatible with the schema SearchModel.js already expects.

mod args;
mod apps;
mod files;
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

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

fn main() {
    let cfg = args::parse();

    if cfg.query.trim().is_empty() {
        emit_error("No query provided");
        std::process::exit(1);
    }

    let mut ranked: Vec<Ranked> = Vec::new();

    // 1. App results (already carry a +0.5 kind bonus → float above file hits).
    for r in apps::search(&cfg.query) {
        ranked.push(Ranked {
            score: r.score,
            item: ResultItem {
                path: r.path,
                name: r.name,
                dir: r.dir,
                kind: r.kind,
                icon: if r.icon.is_empty() { None } else { Some(r.icon) },
            },
        });
    }

    // 2. File results (plocate or fd, noise-filtered, scored).
    for r in files::search(&cfg) {
        ranked.push(Ranked {
            score: r.score,
            item: ResultItem {
                path: r.path,
                name: r.name,
                dir: r.dir,
                kind: r.kind,
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
