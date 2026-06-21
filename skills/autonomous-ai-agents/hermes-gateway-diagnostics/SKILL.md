---
name: hermes-gateway-diagnostics
description: "Systematically diagnose Hermes Gateway health, hung processes, and messaging-platform connectivity failures (Telegram, Discord, API server, etc.)"
version: 1.0.0
platforms: [linux, macos]
---

# Hermes Gateway Diagnostics

Use when the user reports a messaging platform isn't responding, the bot is silent, messages get no reply, or the gateway appears unreachable. Covers the systematic root-cause path from platform-level state down to model-response failures.

## Quick Triage

Three most common failure modes:

| Symptom | Likely cause | Quick fix |
|---------|-------------|-----------|
| Platform says "connected" but no response for hours | Model/provider stuck; gateway hung on a bad turn | Restart gateway (`systemctl --user restart hermes-gateway` or kill PID and let s6 respawn) |
| Model returns garbled/refusal text (Chinese error, "I cannot", empty response) | Provider issue — model down, rate-limited, or producing bad output | Switch model (`hermes model` or edit `config.yaml` → `model.default`) |
| Gateway process dead (no PID) | s6 auto-restart should fire within seconds | Check `systemctl --user status hermes-gateway`; if in crash loop, check logs for OOM or import error |

## Full Diagnosis Workflow

### 1. Check Gateway State File

The file `gateway_state.json` in Hermes home holds platform connection health:

```json
{
  "pid": 7204,                          // gateway PID
  "gateway_state": "running",            // running | stopped | crashed
  "platforms": {
    "telegram": {
      "state": "connected",              // connected | disconnected | error
      "error_code": null,
      "error_message": null,
      "updated_at": "..."                // timestamp — if stale (hours/days old), gateway may be hung
    }
  }
}
```

Key checks:
- `gateway_state` must be `"running"`
- Target platform state must be `"connected"` with no errors
- `updated_at` should be recent — if it's hours old even though the PID is alive, the process is hung

### 2. Verify Process Is Alive

Check the PID from `gateway_state.json` against the process table via `/proc`:

```python
import os
pid = 7204
try:
    os.kill(pid, 0)
    print("PID alive")
except OSError:
    print("PID dead — s6 should auto-restart")
```

List all Hermes-related processes from `/proc` to see s6 supervision hierarchy:

```
PID 30:  s6-supervise main-hermes
PID 140: s6-supervise gateway-default          # supervisor
PID 143: s6-supervise gateway-default/log      # log supervisor
PID 7204: python3 ... hermes gateway run       # actual gateway process
```

The gateway PID being alive does NOT mean it's healthy — it can be stuck on a model call.

### 3. Check Gateway Logs

s6-supervised gateways write logs to `~/.hermes/logs/gateways/default/current` (or equivalent Hermes home path).

Look for:
- **"Hermes Gateway Starting"** — timestamps reveal restart frequency. A gateway restarting every few minutes is in a crash loop.
- **Stream interrupted by network error** — transient provider issues
- **Iteration budget exhausted** — a response ran too many tool calls
- **Last log entry age** — if the log went silent hours ago but the PID is alive, the gateway is hung

### 4. Query Sessions for the Affected Platform

Use `execute_code` with sqlite3 to inspect `state.db`:

```python
import sqlite3
conn = sqlite3.connect("~/.hermes/state.db")
c = conn.cursor()
c.execute("""
    SELECT id, title, source, user_id, started_at, ended_at, message_count
    FROM sessions
    WHERE source = 'telegram'
    ORDER BY started_at DESC
    LIMIT 5
""")
```

Check for:
- **No ended_at** — session is still active (may mean gateway is waiting on the model)
- **Recent session with few messages** — user sent a message but got no/broken response

### 5. Trace the Last Conversation

Pull all messages from the latest active session:

```python
c.execute("""
    SELECT role, content, timestamp
    FROM messages
    WHERE session_id = ?
    ORDER BY timestamp ASC
""", (session_id,))
```

Look for signs of trouble:
- Assistant response is empty or contains a model refusal ("I cannot provide...", "我无法给与相关内容")
- Tool results that failed or timed out
- The assistant made excessive tool calls before giving a bad answer

### 6. Root Cause Analysis

| Finding | Root Cause | Action |
|---------|-----------|--------|
| Model gives broken/refusal responses | Provider issue with the configured model | Switch model or provider; check OpenRouter status |
| Gateway PID alive but state/logs stale for hours | Process hung on a model call that never completes | Kill PID; s6 auto-restarts it fresh |
| Gateway in crash loop (restarting every few minutes) | Config error, missing env var, corrupted state | Check `hermes doctor --fix` |
| Platform disconnected with error | Invalid token, revoked access, API change | Re-authenticate the platform (`hermes gateway setup`) |
| Gateway state says "running" but no platform connected | Platform not configured or disabled | Check `platform_toolsets` in config and .env for tokens |

## Pitfalls

- **"Connected" does not mean "responsive"** — the Telegram API reports connected even when the gateway's model call loop is stuck. Always correlate with log age and session state.
- **Stale state file** — `gateway_state.json` may not get updated when the process hangs. Always cross-check PID liveness and log timestamps.
- **No terminal tool available** — you can still diagnose using `read_file`, `search_files`, and `execute_code` with sqlite3 queries on `state.db`.
- **s6 hides crash-to-restart transitions** — if the gateway crashes, s6 restarts it silently. The gateway_state.json and PID file may briefly reference the old process. Check log timestamps for gaps.
- **Model failures look like gateway failures** — a broken model response (refusal, garbled text, empty string) gets delivered to the user, making the gateway appear "working" when the real problem is upstream. Always trace the last conversation's messages.
- **`.env` is unreadable** — the credential store is access-denied by Hermes tooling. Check telegram bot token via `hermes gateway setup` or by verifying the platform connects.