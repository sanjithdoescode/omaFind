// src/apps.rs – Desktop-entry scanner.  Produces app results that always float
// above file results in the merged ranking thanks to a +0.5 kind bonus.

use crate::score;

// ---------------------------------------------------------------------------
// Public result type
// ---------------------------------------------------------------------------

pub struct AppResult {
    pub path: String,  // path to the .desktop file
    pub name: String,  // human-readable app name (from Name=)
    pub dir: String,   // "Applications" or "~/Applications"
    pub kind: String,  // always "app"
    pub icon: String,  // icon name or path (from Icon=)
    pub score: f32,
}

// ---------------------------------------------------------------------------
// Desktop-entry parser
// ---------------------------------------------------------------------------

#[derive(Default)]
struct DesktopEntry {
    entry_type: String,   // must be "Application"
    name: String,
    generic_name: String,
    comment: String,
    icon: String,
    keywords: Vec<String>,
    no_display: bool,
    hidden: bool,
}

/// Parse the `[Desktop Entry]` section of a `.desktop` file.
/// Returns `None` if the entry should not appear in search results.
fn parse_desktop(path: &str) -> Option<DesktopEntry> {
    let content = std::fs::read_to_string(path).ok()?;
    let mut entry = DesktopEntry::default();
    let mut in_section = false;

    for line in content.lines() {
        let line = line.trim();

        if line.starts_with('[') {
            in_section = line == "[Desktop Entry]";
            continue;
        }
        if !in_section || line.is_empty() || line.starts_with('#') {
            continue;
        }

        let Some((key, val)) = line.split_once('=') else { continue };
        let key = key.trim();
        let val = val.trim();

        // Skip localised variants like Name[de]=, GenericName[fr]=, etc.
        if key.contains('[') {
            continue;
        }

        match key {
            "Type"        => entry.entry_type   = val.to_string(),
            "Name"        => entry.name         = val.to_string(),
            "GenericName" => entry.generic_name = val.to_string(),
            "Comment"     => entry.comment      = val.to_string(),
            "Icon"        => entry.icon         = val.to_string(),
            "Keywords"    => {
                entry.keywords = val
                    .split(';')
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .map(str::to_string)
                    .collect();
            }
            "NoDisplay" => entry.no_display = val.eq_ignore_ascii_case("true"),
            "Hidden"    => entry.hidden     = val.eq_ignore_ascii_case("true"),
            _           => {}
        }
    }

    // Only surface runnable, visible applications.
    if entry.name.is_empty()
        || entry.no_display
        || entry.hidden
        || !entry.entry_type.eq_ignore_ascii_case("Application")
    {
        return None;
    }

    Some(entry)
}

// ---------------------------------------------------------------------------
// Scoring
// ---------------------------------------------------------------------------

/// Best match score of `query` across all text fields of the entry.
fn app_score(entry: &DesktopEntry, query: &str) -> f32 {
    let mut best = score::match_score(query, &entry.name);

    if !entry.generic_name.is_empty() {
        best = best.max(score::match_score(query, &entry.generic_name) * 0.85);
    }
    if !entry.comment.is_empty() {
        best = best.max(score::match_score(query, &entry.comment) * 0.60);
    }
    for kw in &entry.keywords {
        best = best.max(score::match_score(query, kw) * 0.80);
    }

    best
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Scan system and user `.desktop` files and return those matching `query`.
///
/// User-local entries are scanned first; duplicates by name are deduplicated
/// so a local override silently wins over the system-wide entry.
pub fn search(query: &str) -> Vec<AppResult> {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/root".to_string());

    // Local first (higher priority), system second.
    let dirs = [
        format!("{}/.local/share/applications", home),
        "/usr/share/applications".to_string(),
    ];

    let mut results: Vec<AppResult> = Vec::new();
    let mut seen_names: std::collections::HashSet<String> = std::collections::HashSet::new();

    for dir in &dirs {
        let read_dir = match std::fs::read_dir(dir) {
            Ok(d) => d,
            Err(_) => continue,
        };

        for entry in read_dir.flatten() {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("desktop") {
                continue;
            }
            let path_str = path.to_string_lossy().into_owned();
            let Some(desktop) = parse_desktop(&path_str) else { continue };

            let raw = app_score(&desktop, query);
            if raw < 0.15 {
                continue;
            }

            // Deduplicate: local entry wins (it's scanned first).
            let name_key = desktop.name.to_lowercase();
            if !seen_names.insert(name_key) {
                continue;
            }

            let dir_label = if path_str.starts_with(&home) {
                "~/Applications".to_string()
            } else {
                "Applications".to_string()
            };

            results.push(AppResult {
                path: path_str,
                name: desktop.name,
                dir: dir_label,
                kind: "app".to_string(),
                icon: desktop.icon,
                // +0.5 kind bonus ensures apps float above file results at equal query match.
                score: raw + 0.50,
            });
        }
    }

    results
}
