---
name: subagent-delegation
description: "Delegate work to Hermes subagent profiles via delegate_task — patterns, constraints, and pitfalls for team-agent workflows (Charmander/Squirtle/Pikachu)."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [delegation, subagents, multi-agent, profiles, team]
    related_skills: [hermes-agent, claude-code, codex, opencode]
---

# Subagent Delegation

Delegate work to Hermes subagent profiles using the `delegate_task` tool. This skill covers practical patterns for spawning team agents (Charmander, Squirtle, Pikachu profiles) and the constraints of Hermes' subagent model.

## When to Use delegate_task

- **Reasoning-heavy subtasks** (debugging, code review, research synthesis)
- **Tasks that flood your context** with intermediate data
- **Parallel independent workstreams** (research A and B simultaneously)
- **Team agent workflows** — Charmander (testing), Squirtle (DevOps), Pikachu (coding)

## When NOT to Use delegate_task

- **Mechanical multi-step work with no reasoning** → use `execute_code`
- **Single tool call** → just call the tool directly
- **Tasks needing user interaction** → subagents cannot use clarify
- **Durable long-running work** → use `cronjob` or `terminal(background=True, notify_on_complete=True)`

## Critical Constraint: Subagents Cannot Execute Commands

**Subagents (even with the 'terminal' toolset) CAN write files but CANNOT run terminal commands or execute_code.** This is a fundamental tool constraint, not an environment issue.

### What works in a subagent:
- `write_file`, `read_file`, `search_files`, `patch` (file tools)
- `web_search`, `web_extract` (web tools)
- `browser_navigate`, `browser_*` (browser tools)
- `skill_view`, `skills_list` (skill tools)

### What does NOT work:
- `execute_code` (blocked for all leaf/orchestrator subagents)
- Terminal/command execution (blocked for all subagents)
- `delegate_task` (blocked for leaf subagents)
- `memory` (blocked for all subagents)
- `clarify` (blocked for all subagents)

### The Script-Write-Then-Execute Pattern

For any task requiring shell execution (git push, npm build, deploy scripts, Docker builds, CI/CD):

1. **Subagent writes a self-contained script** via `write_file` — a bash/Python script that is fully idempotent and self-contained
2. **Subagent returns the script path** in its summary
3. **Parent agent runs the script** using `execute_code` with `subprocess.run(["bash", "/path/to/script.sh"], ...)` or via terminal

Example from the Squirtle workflow:
```
Parent delegates to Squirtle (DevOps profile)
  → Squirtle writes deploy.sh (git init, repo creation, push)
  → Squirtle returns: "script at /opt/data/weather-app/deploy.sh"
  → Parent runs: bash deploy.sh
```

## Context is Everything

Subagents have **NO memory** of your conversation. Pass all relevant information via the `context` field:

- File paths (absolute paths preferred)
- Error messages and stack traces
- Project structure
- User preferences, language, style requirements
- Constraints and edge cases
- Previous attempts and what failed

The more specific you are, the better the subagent performs.

## Verification Pattern

**Subagent summaries are self-reports, not verified facts.** A subagent that claims "uploaded successfully" or "file written" may be wrong. Always verify:

1. For file operations: stat the file, read back the content
2. For HTTP/publishing operations: fetch the URL, check the HTTP status
3. For git operations: check `git status`, verify remote, confirm push
4. For test results: re-run the tests after the subagent returns

## Toolsets for Common Task Types

Pass the right toolsets to limit token overhead:

| Task | Toolsets | Reason |
|------|----------|--------|
| Code writing | `['file']` | Write files, no network needed |
| Research | `['web', 'file']` | Search + save to file |
| Testing | `['file']` | Read code, write tests |
| DevOps/Deploy | `['file', 'web']` | Write scripts (web for API calls in script) |
| Code review | `['file']` | Read files, write review |
| Full stack | `['terminal', 'file', 'web']` | All tools (terminal is for future verification) |

Note: even with 'terminal' passed, subagents cannot actually run shell commands — the toolset lets them reference terminal context but execution is blocked.

## Team Agent Profiles

This user has three team agent profiles configured as independent Hermes profiles:

| Agent | Profile | Role |
|-------|---------|------|
| Charmander | `/opt/data/profiles/charmander/config.yaml` | Testing — writes unit/integration tests, runs test suites |
| Squirtle | `/opt/data/profiles/squirtle/config.yaml` | DevOps — git, Docker, CI/CD, deployment scripts |
| Pikachu | Not yet created | Coding — writes application code |

### Delegation Rules
1. **Delegate directly** — when the user says "ask X to do Y", spawn the subagent immediately. Skip the "Ash presents to the team" loop.
2. **Fix provider config first** — check the profile's `config.yaml` has a `provider` field set (not empty). If it's missing or empty, set it before delegating. Profiles without a provider cannot run independently.
3. **One task per agent** — delegate the most relevant profile. Charmander for tests, Squirtle for push/deploy, Pikachu for code.
4. **Verify after delegation** — run tests after Charmander returns, check git status after Squirtle returns.

## Batch Delegation

For parallel independent tasks, use the `tasks` array:

```python
delegate_task(tasks=[
    {"goal": "Research solution for problem X", "context": "...", "toolsets": ["web", "file"]},
    {"goal": "Write test suite for module Y", "context": "...", "toolsets": ["file"]},
    {"goal": "Create Dockerfile for project Z", "context": "...", "toolsets": ["file", "web"]},
])
```

Max 3 concurrent tasks. All run in parallel; results returned together.

## Role Types

- **leaf** (default) — focused worker. Cannot delegate further, cannot use memory/clarify/execute_code.
- **orchestrator** — can spawn its own workers via delegate_task. Bounded by `delegation.max_spawn_depth`.

For this user: max_spawn_depth=1, so orchestrator is silently forced to leaf.

## Pitfalls

1. **Subagent writes script but can't run it.** The parent MUST execute the script after delegation returns. The pattern: subagent path → read_file to verify → bash script.sh to execute.

2. **No GitHub token on fresh systems.** If the subagent needs to push to GitHub, check for GITHUB_TOKEN or gh CLI auth before delegating. The subagent can write a deploy script, but if there's no token, the script will fail when the parent runs it. Check the environment first.

3. **Per-profile provider config.** Each Hermes profile needs its own `provider` field in `config.yaml`. The default config at ~/.hermes/config.yaml is NOT inherited. Always verify before delegating to a profile.

4. **Language/tone contamination.** Subagents default to English even if the user is writing in another language. Pass language preferences explicitly in the `context` field.

5. **Subagent goals must be self-contained.** The subagent knows nothing about your conversation history. Even file paths need to be absolute. Never reference "the file I mentioned earlier" — spell it out.

6. **Don't trust happy-path summaries.** A subagent that prints "Success!" may have hit an error it didn't detect. Always verify with a file read, HTTP check, or test re-run.

## Quick Reference

```python
# Single task
delegate_task(
    goal="Write tests for module X at /path/to/file.js",
    context="Existing tests use vitest + happy-dom. Tests go in /path/to/tests/",
    toolsets=["file"]
)
# → Subagent writes test files
# → Parent runs: bash -c "cd /path && npx vitest run"

# Batch (parallel)
delegate_task(tasks=[
    {"goal": "Task A", "toolsets": ["file"]},
    {"goal": "Task B", "toolsets": ["web"]},
])

# DevOps pattern (script-write-then-execute)
delegate_task(
    goal="Write deploy script for project at /path/to/project",
    context="... path, repo name, token location ...",
    toolsets=["file"]
)
# → Subagent writes /path/to/project/deploy.sh
# → Parent runs: bash /path/to/project/deploy.sh
```