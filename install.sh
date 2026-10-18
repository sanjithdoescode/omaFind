#!/usr/bin/env bash
# install.sh – Build omafind-search and install the binary into bin/.
# Run once after cloning, or whenever the Rust source changes.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PLUGIN_DIR"

echo "📦 Building omafind-search (Rust)..."
cargo build --release

mkdir -p bin
cp target/release/omafind-search bin/omafind-search
chmod +x bin/omafind-search

echo "✅ Done — binary at: $PLUGIN_DIR/bin/omafind-search"
echo "   Reload the plugin to apply: omarchy plugin reload sanjith.omafind"
