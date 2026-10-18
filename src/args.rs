// src/args.rs – CLI argument parser (no external deps).

/// Runtime configuration parsed from argv.
pub struct Config {
    pub query: String,
    pub limit: usize,
    pub home_only: bool,
    pub live: bool,
    pub save_pos: bool,
}

pub fn parse() -> Config {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    let mut query = String::new();
    let mut limit = 50usize;
    let mut home_only = true;
    let mut live = false;
    let mut save_pos = false;

    let mut i = 0;
    while i < argv.len() {
        match argv[i].as_str() {
            "--save-pos" => {
                save_pos = true;
                i += 1;
            }
            "--query" if i + 1 < argv.len() => {
                query = argv[i + 1].clone();
                i += 2;
            }
            "--limit" if i + 1 < argv.len() => {
                limit = argv[i + 1].parse::<usize>().unwrap_or(50).clamp(1, 200);
                i += 2;
            }
            "--home-only" => {
                home_only = true;
                i += 1;
            }
            "--all" => {
                home_only = false;
                i += 1;
            }
            "--live" => {
                live = true;
                i += 1;
            }
            _ => {
                i += 1;
            }
        }
    }

    Config { query, limit, home_only, live, save_pos }
}
