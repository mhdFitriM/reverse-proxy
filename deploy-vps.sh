#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$ROOT_DIR"

if [[ ! -f ".env" ]]; then
  echo "Missing .env in $ROOT_DIR"
  echo "Create it from .env.example first."
  exit 1
fi

echo "Deploying shared reverse proxy from $ROOT_DIR"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Pulling latest Git changes..."
  git pull --ff-only
fi

docker compose up -d
echo "Reverse proxy deployment complete."
