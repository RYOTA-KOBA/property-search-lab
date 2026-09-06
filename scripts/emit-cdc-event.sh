#!/bin/bash
# scripts/emit-cdc-event.rb のラッパー。使い方: ./scripts/emit-cdc-event.sh <insert|update|delete> <table> <id>
set -euo pipefail

cd "$(dirname "$0")/.."
bundle exec ruby scripts/emit-cdc-event.rb "$@"
