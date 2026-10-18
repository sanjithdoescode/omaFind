// src/files.rs – File search layer: plocate/fd runner, noise filter, ranking.

use crate::{args::Config, score};

// ---------------------------------------------------------------------------
// Noise filter
// ---------------------------------------------------------------------------

/// Path segments that indicate a result is almost certainly noise.
/// Any path containing one of these substrings is excluded.
const NOISE_SEGMENTS: &[&str] = &[
    "/.cache/",
    "/node_modules/",
    "/__pycache__/",
    "/.bun/",
    "/target/release/",
    "/target/debug/",
    "/target/deps/",
    "/target/incremental/",
    "/.git/",
    "/vendor/",
    "/.cargo/registry/",
    "/.cargo/git/",
    "/.rustup/toolchains/",
    "/site-packages/",
    "/.Trash/",
    "/Trash/",
    "/.npm/_cacache/",
];

/// File suffixes that are always noise (source maps, compiled bytecode, etc.).
const NOISE_SUFFIXES: &[&str] = &[
    ".js.map", ".d.ts.map", ".pyc", ".pyo", ".rlib", ".rmeta",
];

fn is_noise(path: &str) -> bool {
    if NOISE_SEGMENTS.iter().any(|&seg| path.contains(seg)) {
        return true;
    }
    if NOISE_SUFFIXES.iter().any(|&sfx| path.ends_with(sfx)) {
        return true;
    }
    false
}

// ---------------------------------------------------------------------------
// File classification
// ---------------------------------------------------------------------------

fn classify(path: &str) -> &'static str {
    let p = std::path::Path::new(path);
    if p.is_dir() {
        return "dir";
    }
    let ext = p
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_lowercase())
        .unwrap_or_default();

    match ext.as_str() {
        "py" | "js" | "mjs" | "ts" | "tsx" | "jsx" | "rs" | "go" | "c"
        | "cpp" | "h" | "hpp" | "java" | "kt" | "swift" | "rb" | "php"
        | "lua" | "sh" | "bash" | "zsh" | "fish" | "ps1" | "cs" | "dart"
        | "zig" | "ex" | "exs" | "clj" | "scala" | "r" | "m" | "pl"
        | "jl" | "vim" | "el" | "qml" => "code",
        "png" | "jpg" | "jpeg" | "gif" | "webp" | "svg" | "bmp" | "ico"
        | "tiff" | "tif" | "avif" | "heic" | "raw" => "image",
        "mp4" | "mkv" | "avi" | "mov" | "webm" | "flv" | "m4v" | "wmv" => "video",
        "mp3" | "flac" | "ogg" | "wav" | "aac" | "opus" | "m4a" | "wma" => "audio",
        "pdf" => "pdf",
        "zip" | "tar" | "gz" | "bz2" | "xz" | "7z" | "rar" | "zst" => "archive",
        "md" | "txt" | "rst" | "org" | "tex" | "rtf" | "adoc" => "text",
        "json" | "yaml" | "yml" | "toml" | "xml" | "csv" | "tsv"
        | "ini" | "cfg" | "conf" | "env" => "data",
        _ => "file",
    }
}

/// Small bonus for "higher-value" file kinds.
fn kind_boost(kind: &str) -> f32 {
    match kind {
        "text"    => 0.12,
        "pdf"     => 0.10,
        "dir"     => 0.08,
        "code"    => 0.05,
        "data"    => 0.05,
        "image"   => 0.03,
        "audio"   => 0.03,
        "video"   => 0.03,
        _         => 0.0,
    }
}

// ---------------------------------------------------------------------------
// Public result type
// ---------------------------------------------------------------------------

pub struct FileResult {
    pub path: String,
    pub name: String,
    pub dir: String,
    pub kind: String,
    pub score: f32,
}

// ---------------------------------------------------------------------------
// Scoring
// ---------------------------------------------------------------------------

fn score_path(path: &str, query: &str, home: &str) -> FileResult {
    let p = std::path::Path::new(path);
    let basename = p.file_name().and_then(|n| n.to_str()).unwrap_or(path);

    let name_score = score::match_score(query, basename);
    let depth      = score::depth_penalty(path);
    let recency    = score::recency_boost(path);
    let kind       = classify(path);
    let kb         = kind_boost(kind);

    // Name match dominates; depth is subtracted; recency and kind are additive bonuses.
    let total = (name_score * 0.80) - depth + recency + kb;

    let parent = p.parent().and_then(|p| p.to_str()).unwrap_or("");
    let display_dir = if parent.starts_with(home) {
        format!("~{}", &parent[home.len()..])
    } else {
        parent.to_string()
    };

    FileResult {
        path: path.to_string(),
        name: basename.to_string(),
        dir: display_dir,
        kind: kind.to_string(),
        score: total,
    }
}

// ---------------------------------------------------------------------------
// Backend runners
// ---------------------------------------------------------------------------

fn run_plocate(query: &str, home_only: bool, fetch: usize, home: &str) -> Vec<String> {
    let limit_s = fetch.to_string();
    let output = match std::process::Command::new("plocate")
        .args(["-i", "-l", &limit_s, "--", query])
        .output()
    {
        Ok(o) => o,
        Err(_) => return vec![],
    };

    let text = String::from_utf8_lossy(&output.stdout);
    let mut paths: Vec<String> = text.lines().map(|l| l.to_string()).collect();

    if home_only {
        let prefix = format!("{}/", home);
        paths.retain(|p| p.starts_with(&prefix) || p.as_str() == home);
    }

    paths
}

fn run_fd(query: &str, home_only: bool, fetch: usize, home: &str) -> Vec<String> {
    let base = if home_only { home } else { "/" };
    let limit_s = fetch.to_string();
    let output = match std::process::Command::new("fd")
        .args(["--ignore-case", "--max-results", &limit_s, "--", query, base])
        .output()
    {
        Ok(o) => o,
        Err(_) => return vec![],
    };

    String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(|l| l.to_string())
        .collect()
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub fn search(cfg: &Config) -> Vec<FileResult> {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/root".to_string());

    // Fetch a larger candidate pool so ranking has material to work with.
    // After noise filtering we might discard the majority of raw results.
    let fetch = (cfg.limit * 6).min(500);

    let plocate_available = std::path::Path::new("/usr/bin/plocate").exists();
    let use_fd = cfg.live || !plocate_available;

    let raw = if use_fd {
        run_fd(&cfg.query, cfg.home_only, fetch, &home)
    } else {
        run_plocate(&cfg.query, cfg.home_only, fetch, &home)
    };

    raw.into_iter()
        .filter(|p| !is_noise(p))
        .map(|p| score_path(&p, &cfg.query, &home))
        .collect()
}
