---
name: web-app-integration-testing
description: "Integration testing patterns for web applications: server HTTP, DOM rendering, state management, and API mocking with vitest."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos]
tags: [testing, integration, vitest, happy-dom, web-app, dom]
---

# Web App Integration Testing with Vitest

## When to Use

- You need to test a web app's **server layer** (HTTP static file serving, API endpoints, middleware)
- You need to test **DOM rendering** — verifying that data parsing functions correctly populate HTML elements
- You need to test **state management transitions** (loading → success → error view switching)
- You need to test the **integration between data parsing and display rendering**
- You need to test **async data loading flows** with mocked network requests
- The app uses HTML/CSS/JS (no framework) or a lightweight framework with server-rendered HTML

## Overview

Integration tests validate that components work together. For web apps, the key layers are:

| Layer | What It Tests | Tool |
|-------|--------------|------|
| **Server HTTP** | Route handling, status codes, MIME types, 404s | Node `http` module + child process |
| **DOM Rendering** | Data → HTML elements, template output | `happy-dom` in vitest |
| **State Management** | View transitions (empty→loading→dashboard→error) | `happy-dom` in vitest |
| **Async Data Flow** | Fetch calls → loading state → render/error | Mocked fetch + vitest |
| **Parsing→Rendering** | End-to-end: raw API → parsed → displayed on screen | All of the above |

## Skill Structure

This skill has:
- **SKILL.md** (this file) — main patterns and guidance
- `references/vitest-happy-dom-setup.md` — setup steps for vitest + happy-dom
- `references/server-http-testing.md` — child process server testing details
- `references/dom-rendering-helpers.md` — test helper patterns for DOM rendering
- `references/api-mocking-patterns.md` — fetch/API mocking patterns

## Setup

See `references/vitest-happy-dom-setup.md` for detailed installation and configuration.

**Quick setup:**
```bash
npm install --save-dev vitest happy-dom
```

## Core Patterns

### 1. Server HTTP Tests

Tests verify that a Node.js static file server handles HTTP correctly.

**Two approaches:** Choose based on your parallelization needs.

#### Approach A: Inline Server with Random Port (preferred for parallel test suites)

Creates an HTTP server directly in the test process using `server.listen(0)` for automatic port allocation. Vitest runs test files in parallel by default, so fixed ports cause "address in use" failures. Random ports eliminate this entirely.

```javascript
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import http from 'http';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const dir = path.resolve(__dirname, '..');

let server;
let baseUrl;

function createTestServer() {
  return new Promise((resolve, reject) => {
    const srv = http.createServer((req, res) => {
      const filePath = path.join(dir, req.url === '/' ? 'index.html' : req.url);
      const ext = path.extname(filePath);
      const mime = {
        '.html': 'text/html', '.js': 'application/javascript',
        '.css': 'text/css', '.png': 'image/png',
        '.svg': 'image/svg+xml',
      }[ext] || 'text/plain';
      fs.readFile(filePath, (err, data) => {
        if (err) { res.writeHead(404); res.end('Not found'); return; }
        res.writeHead(200, { 'Content-Type': mime });
        res.end(data);
      });
    });
    srv.listen(0, () => {          // port 0 = random available port
      server = srv;
      baseUrl = `http://localhost:${srv.address().port}`;
      resolve();
    });
    srv.on('error', reject);
  });
}

beforeAll(async () => { await createTestServer(); }, 10000);
afterAll(() => { if (server) server.close(); });

function fetchFromServer(urlPath) {
  return new Promise((resolve, reject) => {
    http.get(`${baseUrl}${urlPath}`, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    }).on('error', reject);
  });
}
```

**Advantages over child process approach:**
- No port conflict — zero chance of "address in use" in parallel runs
- No child process lifecycle to manage (no zombie processes on crash)
- Faster startup — no need to wait for subprocess boot
- Works without modifying the server's `PORT` env handling

See `references/server-inline-testing.md` for a complete, copy-ready example file.

#### Approach B: Child Process on Fixed Port (for external servers)

Use when you must test the actual `server.js` file as a separate OS process (e.g., testing startup/restart behaviour, signal handling, or the exact CLI interface).

See `references/server-http-testing.md` for full child-process pattern.

**Key requirement:** The server must accept `process.env.PORT`:
```javascript
// server.js — use env var with fallback
var port = process.env.PORT || 8080;
```

### 2. DOM Rendering Tests (happy-dom)

Tests verify that data-parsing functions output to correct DOM elements.

**Key technique:** Set up the full app DOM structure in `beforeEach`, mirror the app's rendering functions as test helpers, then verify element content.

```javascript
/**
 * @vitest-environment happy-dom
 */
import { describe, it, expect, beforeEach } from 'vitest';
import { parseLocation, parseCurrentWeather, /* ... */ } from '../weather.js';

const $ = (id) => document.getElementById(id);

function setupDOM() {
  document.body.innerHTML = `
    <div id="state-empty" class="state-view active">...</div>
    <div id="state-loading" class="state-view">...</div>
    <div id="state-error" class="state-view">
      <h2 id="error-title">Default</h2>
      <p id="error-message">Default message</p>
    </div>
    <div id="state-dashboard" class="state-view">
      <h1 id="hero-city">—</h1>
      <div id="hero-temp">--<span>°C</span></div>
      ...
    </div>
  `;
}

// Mirror of app's showView function
function showView(viewId) {
  document.querySelectorAll('.state-view').forEach(v => v.classList.remove('active'));
  $(viewId).classList.add('active');
}

// Mirror of app's renderDashboard function
function renderDashboard(data) {
  const location = parseLocation(data);
  const current = parseCurrentWeather(data);
  $('hero-city').textContent = location.name;
  $('hero-temp').innerHTML = `${Math.round(current.temp_c)}<span>°C</span>`;
  // ...
  showView('state-dashboard');
}
```

**Pitfall:** The app's rendering functions are often inside an IIFE in the HTML file and not exportable. Duplicate the logic as test helpers in the test file — this keeps tests decoupled from HTML implementation details while still testing the same behavior.

### 3. State View Transitions

Test that only one state view is active at a time.

```javascript
describe('showView — State transitions', () => {
  beforeEach(() => setupDOM());

  it('switches to loading and deactivates others', () => {
    showView('state-loading');
    expect($('state-loading').classList.contains('active')).toBe(true);
    expect($('state-empty').classList.contains('active')).toBe(false);
    expect($('state-error').classList.contains('active')).toBe(false);
    expect($('state-dashboard').classList.contains('active')).toBe(false);
  });
});
```

### 4. Async Data Loading Flow

Test the full lifecycle: loading → API call → render (or error).

```javascript
it('renders dashboard on successful fetch', async () => {
  const mockFetch = vi.fn().mockResolvedValue(mockApiResponse);
  await loadWeather('Tokyo', 'test-key', mockFetch);
  expect($('state-dashboard').classList.contains('active')).toBe(true);
  expect($('hero-city').textContent).toBe('Tokyo');
});

it('shows error on fetch failure', async () => {
  const mockFetch = vi.fn().mockRejectedValue(new Error('Network failure'));
  await loadWeather('Tokyo', 'test-key', mockFetch);
  expect($('state-error').classList.contains('active')).toBe(true);
  expect($('error-message').textContent).toBe('Network failure');
});
```

**Pitfall:** The `loadWeather` test helper must check for API key before making the fetch call — test this path separately to verify the guard works.

## Pitfalls

1. **IIFE-scoped rendering functions:** If the app's rendering functions are inside an `<script>` IIFE in HTML, you can't import them. Duplicate the rendering logic as test helpers instead of trying to extract them from the HTML.

2. **Port conflicts in parallel test runs:** Vitest runs test files in parallel by default. Fixed-port servers (`TEST_PORT = 8765`) will collide when multiple server-test files exist — one wins, the rest time out with "address in use".  
   **SOLUTION:** Use an **inline server with `server.listen(0)`** (see Approach A above) — the OS assigns a random available port per test file, eliminating conflicts entirely. Reserve the child-process pattern (Approach B) for when you must test the actual server binary; when you do, use a unique port and run those tests sequentially with `vitest --sequence` or `--pool forks --poolOptions.forks.singleFork`.

3. **Server cleanup:** Kill child processes in `afterAll` — without this, zombie processes accumulate and block ports. For inline servers, call `server.close()` in `afterAll`. Both should be wrapped to catch errors:  
   ```javascript
   afterAll(() => { if (serverProcess && !serverProcess.killed) serverProcess.kill(); });
   // or
   afterAll(() => { if (server) server.close(); });
   ```

4. **happy-dom + ES modules:** happy-dom supports ES module imports. Use `@vitest-environment happy-dom` as a docblock comment at the top of the test file. This avoids needing separate vitest configs for node vs DOM tests.

5. **localStorage in happy-dom:** happy-dom doesn't provide localStorage by default. Mock it:
   ```javascript
   if (!window.localStorage) {
     const store = {};
     window.localStorage = {
       getItem: vi.fn((key) => store[key] || null),
       setItem: vi.fn((key, value) => { store[key] = String(value); }),
       removeItem: vi.fn((key) => { delete store[key]; }),
       clear: vi.fn(() => { Object.keys(store).forEach(k => delete store[k]); }),
     };
   }
   ```

6. **Per-file environment:** Use `@vitest-environment happy-dom` as the **first line** of the file. It's a docblock, so it must be inside a comment.

7. **Concurrent requests:** Test that the server handles multiple simultaneous requests without crashes or wrong responses by using `Promise.all`.

## Verification Checklist

- [ ] Server tests start the server, make real HTTP requests, and kill the process
- [ ] DOM tests use happy-dom with proper `@vitest-environment` annotation
- [ ] All state transitions are tested (empty→loading→dashboard, loading→error, etc.)
- [ ] Rendering tests verify actual element content (textContent, innerHTML, src, classList)
- [ ] Error paths are tested: missing API key, network failure, HTTP 400, empty data
- [ ] Async load flow tests check that loading state appears BEFORE await and error/dashboard appears AFTER
- [ ] Existing unit tests still pass alongside integration tests
- [ ] Test server port is configurable via env var (not hardcoded)