// src/save_pos.rs – Atomic position persistence for omaFind overlay.

use std::io::Read;

pub fn run() {
    let mut input = String::new();
    if let Err(e) = std::io::stdin().read_to_string(&mut input) {
        eprintln!("Failed to read stdin: {e}");
        std::process::exit(1);
    }

    let trimmed = input.trim();
    if trimmed.is_empty() {
        return;
    }

    // Verify payload is valid JSON before writing to disk
    if serde_json::from_str::<serde_json::Value>(trimmed).is_err() {
        eprintln!("Invalid JSON in position payload");
        std::process::exit(1);
    }

    let home = std::env::var("HOME").unwrap_or_else(|_| "/root".to_string());
    let state_dir = std::path::PathBuf::from(home).join(".local/state/omafind");

    if let Err(e) = std::fs::create_dir_all(&state_dir) {
        eprintln!("Failed to create state dir: {e}");
        std::process::exit(1);
    }

    let pid = std::process::id();
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);

    let tmp_path = state_dir.join(format!(".pos.{pid}_{nonce}.tmp"));
    let target_path = state_dir.join("position.json");

    if let Err(e) = std::fs::write(&tmp_path, trimmed) {
        eprintln!("Failed to write temporary position file: {e}");
        std::process::exit(1);
    }

    if let Err(e) = std::fs::rename(&tmp_path, &target_path) {
        eprintln!("Failed to rename temporary position file: {e}");
        let _ = std::fs::remove_file(&tmp_path);
        std::process::exit(1);
    }
}
