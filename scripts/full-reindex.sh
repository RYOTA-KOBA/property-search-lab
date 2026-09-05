#!/bin/bash
# scripts/full-reindex.rb のラッパー。例: ./scripts/full-reindex.sh properties_v2
set -euo pipefail

cd "$(dirname "$0")/.."
bundle exec ruby scripts/full-reindex.rb "${1:-properties_search}"
