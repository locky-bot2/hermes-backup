#!/bin/bash
# Hermes VPS Backup Script
# Backs up all config, skills, profiles, and state to GitHub
# Runs via cron job - no_agent=True

set -e
REPO_DIR="/opt/data"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M UTC")

cd "$REPO_DIR"

# Step 1: Add all changes (respects .gitignore)
git add -A

# Step 2: Check if there's anything to commit
if git diff --cached --quiet; then
  echo "[$TIMESTAMP] No changes to back up. Skipping commit."
  exit 0
fi

# Step 3: Commit and push
CURRENT_TIME=$(date +"%Y-%m-%d_%H-%M")
git commit -m "Auto-backup: $CURRENT_TIME UTC

Hermes VPS weekly backup - $(hostname)
Includes: config, profiles, skills, cron, memories, plugins, webui-mvp"
git push origin main

echo "[$TIMESTAMP] Backup complete - $(git rev-parse --short HEAD)"