---
name: hermes-vps-migration
description: Complete guide for migrating Hermes Agent to a new VPS by restoring from GitHub backup
---

# Hermes VPS Migration Guide

Use when migrating Hermes Agent to a new VPS after backing up to `github.com/locky-bot2/hermes-backup`.

## Restore Steps

1. **On the new VPS**, clone the backup repo:
```bash
cd /opt/data
git clone https://github.com/locky-bot2/hermes-backup.git .
```

2. **Install Hermes Agent** (v0.16.0):
```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | sh
```

3. **Restore the GITHUB_TOKEN** in the new VPS environment so cron jobs and git operations work.

4. **Restore Telegram gateway credentials** (if using Telegram):
   - The gateway config is in config.yaml under `gateways.telegram`
   - Telegram API tokens are typically in `.env` or auth files not included in the backup
   - Reconnect Telegram after Hermes is running: `hermes gateway add telegram`

5. **Verify everything migrated**:
```bash
# Check profiles
ls -la /opt/data/profiles/

# Check config
hermes config show

# Check skills
hermes skills list

# Check cron jobs
hermes cron list

# Start Hermes
hermes run
```

## What's in the Backup

Repo: `github.com/locky-bot2/hermes-backup`

| Directory | Contents |
|-----------|----------|
| config.yaml | Hermes Agent configuration |
| profiles/ | Agent profiles (charmander, pikachu, squirtle) with their skills |
| skills/ | All installed skills (400+) |
| cron/ | Cron job definitions and output history |
| memories/ | MEMORY.md (agent notes) + USER.md (user profile) |
| plugins/ | Hermes plugins (achievements) |
| sessions/ | Session history |
| webui-mvp/ | WebUI MVP project |
| SOUL.md | Agent soul/personality file |
| gateway_state.json, channel_directory.json | Gateway connection state |

## What is NOT in the Backup

- `.env` / `auth.json` / `credentials.json` (secrets)
- `.npm/` cache (reinstalled by Hermes setup)
- `cache/`, `logs/`, `.local/` (runtime artifacts)
- `weather-app/` (excluded by user request)