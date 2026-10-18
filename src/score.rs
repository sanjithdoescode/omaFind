// src/score.rs – Scoring primitives: trigram similarity, depth penalty, recency boost.

use std::collections::HashSet;

// ---------------------------------------------------------------------------
// Trigram fuzzy matching
// ---------------------------------------------------------------------------

/// Produce trigrams from a string, padded with spaces for edge matching.
fn trigrams(s: &str) -> impl Iterator<Item = [char; 3]> {
    // Pad with two spaces on each side so word-start/end trigrams are captured.
    let chars: Vec<char> = format!("  {}  ", s.to_lowercase()).chars().collect();
    (0..chars.len().saturating_sub(2))
        .map(move |i| [chars[i], chars[i + 1], chars[i + 2]])
}

/// Jaccard similarity of the trigram sets of two strings. Returns 0.0–1.0.
pub fn trigram_similarity(a: &str, b: &str) -> f32 {
    if a.is_empty() || b.is_empty() {
        return 0.0;
    }
    let a_set: HashSet<[char; 3]> = trigrams(a).collect();
    let b_set: HashSet<[char; 3]> = trigrams(b).collect();
    let intersection = a_set.intersection(&b_set).count();
    let union = a_set.len() + b_set.len() - intersection;
    if union == 0 {
        return 0.0;
    }
    intersection as f32 / union as f32
}

// ---------------------------------------------------------------------------
// Match scoring
// ---------------------------------------------------------------------------

/// Check whether `query` matches the word-start initials of `text`.
///
/// Example: "bb" matches "Brave Browser" (B·rave B·rowser).
fn initials_match(query: &str, text: &str) -> bool {
    let q: Vec<char> = query.to_lowercase().chars().collect();
    if q.is_empty() {
        return false;
    }
    let initials: Vec<char> = {
        let mut out = Vec::new();
        let mut new_word = true;
        for ch in text.to_lowercase().chars() {
            if ch == ' ' || ch == '-' || ch == '_' || ch == '.' {
                new_word = true;
            } else if new_word {
                out.push(ch);
                new_word = false;
            }
        }
        out
    };
    if initials.len() < q.len() {
        return false;
    }
    initials.iter().take(q.len()).eq(q.iter())
}

/// Score how well `query` matches `text`.
///
/// Returns a value in roughly 0.0–1.0:
/// - 1.0   exact match
/// - 0.90  prefix match
/// - 0.80  initials/acronym match  (e.g. "bb" → "Brave Browser")
/// - 0.75  substring match
/// - 0.0–0.49 fuzzy trigram (threshold scales with query length)
/// - 0.0   no meaningful match
pub fn match_score(query: &str, text: &str) -> f32 {
    let q = query.to_lowercase();
    let t = text.to_lowercase();
    if q.is_empty() || t.is_empty() {
        return 0.0;
    }
    if t == q {
        return 1.0;
    }
    if t.starts_with(&q) {
        return 0.90;
    }
    if initials_match(&q, &t) {
        return 0.80;
    }
    if t.contains(&q) {
        return 0.75;
    }
    // Short queries have fewer trigrams so Jaccard is naturally low; be more lenient.
    let threshold = if q.len() <= 3 { 0.15 } else { 0.30 };
    let sim = trigram_similarity(&q, &t);
    if sim >= threshold { sim * 0.70 } else { 0.0 }
}

// ---------------------------------------------------------------------------
// Modifiers
// ---------------------------------------------------------------------------

/// Penalty for deep filesystem nesting (prefer shallower hits). Returns 0.0–0.35.
pub fn depth_penalty(path: &str) -> f32 {
    let depth = path.bytes().filter(|&b| b == b'/').count();
    (depth.saturating_sub(5) as f32 * 0.04).min(0.35)
}

/// Boost for recently modified files. Returns 0.0–0.30.
pub fn recency_boost(path: &str) -> f32 {
    use std::time::{SystemTime, UNIX_EPOCH};

    let meta = match std::fs::metadata(path) {
        Ok(m) => m,
        Err(_) => return 0.0,
    };
    let mtime = match meta.modified() {
        Ok(t) => t,
        Err(_) => return 0.0,
    };

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    let mt = mtime
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    let age_days = now.saturating_sub(mt) as f32 / 86_400.0;
    if age_days < 1.0 {
        0.30
    } else if age_days < 7.0 {
        0.20
    } else if age_days < 30.0 {
        0.10
    } else {
        0.0
    }
}
