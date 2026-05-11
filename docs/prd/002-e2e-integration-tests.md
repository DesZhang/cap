# PRD: End-to-End Integration Tests for Cap Deployment

## Problem Statement

The Cap standalone deployment has been modified to support Redis Cluster, key prefixing, and self-hosted assets (PRD 001). However, there are no integration tests proving the full workflow works end-to-end: a browser loads self-hosted assets from Cap, solves the PoW challenge, sends the token to a downstream backend, and the backend verifies it with Cap. Additionally, the upstream token TTL is hardcoded to 2 hours — a security concern for production deployments — and the Docker Compose file only supports cluster-mode Redis, making single-node testing impossible without manual configuration.

## Solution

Build a comprehensive end-to-end integration test suite that:

- Builds the Cap Docker image once and uses it for both deployment packaging and testing
- Runs a full browser-based test using Playwright across all four widget integration modes (Widget, Programmatic, Floating, Accessibility)
- Proves the self-hosted asset chain works by hard-blocking CDN requests and forcing all WASM/PoW execution through the Cap server's `/assets/` routes
- Tests API failure modes (empty token, fabricated token, replay, expiry, Cap-down, wrong secret)
- Makes token TTL configurable via environment variable (defaulting to the upstream 2 hours) so production deployments can set a tighter window and tests can use a short TTL for expiry scenarios
- Makes the Docker Compose configuration work with both cluster-mode and standalone Redis

## User Stories

1. As a Cap operator, I want a single Docker image that works for both production deployment and integration testing, so that I can validate the exact artifact I'll deploy.
2. As a Cap operator, I want token TTL configurable via an environment variable, so that I can set a tighter expiry window (e.g. 5 minutes) instead of the upstream default of 2 hours.
3. As a Cap operator, I want the Docker Compose file to work with single-node Redis, so that I can run integration tests without setting up a Redis Cluster.
4. As a Cap operator, I want the Docker Compose file to continue working with Redis Cluster, so that my existing production deployment is not broken.
5. As a Cap developer, I want end-to-end integration tests covering the Programmatic widget mode, so that I can verify the JS API → WASM PoW → token → backend verify flow works with self-hosted assets.
6. As a Cap developer, I want end-to-end integration tests covering the standard Widget mode, so that I can verify the `cap-widget` element auto-solves, injects a hidden token input, and the backend verifies it.
7. As a Cap developer, I want end-to-end integration tests covering the Floating/Invisible mode, so that I can verify the floating widget trigger → solve → verify flow works.
8. As a Cap developer, I want end-to-end integration tests covering the Accessibility mode, so that I can verify it loads assets and solves challenges identically to the standard widget.
9. As a Cap developer, I want the integration tests to assert zero CDN requests, so that I can be certain all assets (widget.js, WASM binary) are served from the Cap server in an air-gapped environment.
10. As a Cap developer, I want an API test that sends an empty token to the backend, so that I can verify it returns 400.
11. As a Cap developer, I want an API test that sends a null/missing token to the backend, so that I can verify it returns 400.
12. As a Cap developer, I want an API test that sends a fabricated token to the backend, so that I can verify it returns 401.
13. As a Cap developer, I want an API test that replays a real browser-solved token, so that I can verify Cap's `getdel` atomic consumption prevents replay attacks (401 on second use).
14. As a Cap developer, I want an API test that sends a real token after its TTL has expired, so that I can verify expired tokens are rejected (401).
15. As a Cap developer, I want an API test that stops the Cap container and then sends a real token to the backend, so that I can verify the backend returns 503 gracefully when Cap is unavailable.
16. As a Cap developer, I want an API test that sends a real token to a backend configured with the wrong site secret, so that I can verify secret mismatches are rejected (401).
17. As a Cap developer, I want the backend to return status-code-only responses with no body on all verification outcomes, so that attackers gain no information from error details.
18. As a Cap developer, I want the integration test script to flush Redis after each run, so that tests are clean and reliable with no state leakage.
19. As a Cap developer, I want the orchestration script to register a fresh site key per test run, so that no stale tokens from previous runs interfere.
20. As a Cap developer, I want the orchestration script to wait for each service to be healthy before proceeding, so that test failures are due to real bugs and not race conditions.
21. As a Cap developer, I want the frontend to set `CAP_CUSTOM_WASM_URL` pointing to the Cap server's asset route, so that the WASM binary is loaded from the Cap server and not from a CDN.

## Implementation Decisions

### Token TTL Configuration

- The hardcoded `TOKEN_TTL_MS` constant (2 hours) becomes configurable via a `TOKEN_TTL_MS` environment variable.
- Default remains 2 hours (`2 * 60 * 60 * 1000`) for upstream compatibility.
- Integration tests set `TOKEN_TTL_MS=10000` (10 seconds) to enable expiry testing without long waits.
- This is a one-line change in the challenge handler module: read from `process.env.TOKEN_TTL_MS` with the current value as fallback.

### Dual-Mode Docker Compose

- The production Docker Compose file gains a `REDIS_URL` environment variable with a default of `redis://localhost:6379`.
- The existing `REDIS_CLUSTER_URLS` and `REDIS_CLUSTER_PASSWORD` variables lose their required (`:?`) syntax and default to empty.
- `ADMIN_KEY` remains required with `:?` syntax — it is needed in both modes.
- `REDIS_KEY_PREFIX` is exposed as a configurable variable with default `cap:`.
- The ioredis adapter's existing logic (cluster if `REDIS_CLUSTER_URLS` is set, standalone otherwise) handles mode selection — no adapter changes needed.
- Comments in the compose file explain which variables to set for each mode.

### Self-Hosted WASM Configuration

- The frontend's HTML gains a `<script>` block before the widget script that sets `window.CAP_CUSTOM_WASM_URL` to the Cap server's `/assets/cap_wasm_bg.wasm` route.
- The widget script continues to load from `/assets/widget.js` on the Cap server.

### E2E Test Project

- A new `e2e/` directory at the repository root with its own `package.json` and Playwright dependency.
- Playwright is the browser automation framework — it can wait for async widget solving, intercept network requests, and extract DOM values.
- Four separate test files, one per widget mode, each proving the full challenge-solve-verify cycle.

### CDN Enforcement

- Every Playwright test hard-blocks requests to `cdn.jsdelivr.net` via `page.route('**/cdn.jsdelivr.net/**', route => route.abort())`.
- This acts as a negative assertion: if upstream widget code changes and adds a new CDN dependency, the test catches it immediately.
- It also simulates the air-gapped production environment where no CDN access is available.

### Orchestration Script

- A single `run-e2e.sh` at the repository root handles the entire 5-phase pipeline.
- Phase 1 (Bootstrap): Start `redis-server` on a test port → start Cap Docker container with `TOKEN_TTL_MS=10000` and `REDIS_URL` pointing to host Redis → wait for Cap healthcheck via `/assets/widget.js` → authenticate to Cap admin API → register site key → start backend on :8080 with site key and secret as CLI args → start a second backend on :8081 with wrong secret for the wrong-secret test → start frontend with `VITE_CAP_SITE_KEY` env var → wait for all services healthy.
- Phase 2 (Playwright): Run all four browser tests. Each test solves the challenge, extracts the token, sends it to the backend, asserts 200. Tests also harvest tokens to a JSON temp file for subsequent phases.
- Phase 3 (API failure tests): Read harvested tokens from the temp file. Execute curl-based assertions: fabricated token → 401, empty token → 400, null token → 400, replay harvested token → 401, wait 12s then expired token → 401.
- Phase 4 (Infrastructure failure tests): Stop Cap container → send real token to backend → assert 503. Send real token to wrong-secret backend on :8081 → assert 401.
- Phase 5 (Teardown): Kill all processes (frontend, backend instances, Cap container, redis-server). Run `redis-cli FLUSHALL`.

### Service Ready Detection

- Redis: `redis-cli ping` → expect `PONG`
- Cap container: `curl -sf http://localhost:3000/assets/widget.js > /dev/null` → expect 200
- Backend: `curl -sf -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d '{}' http://localhost:8080/api/cap/verify` → expect 400 (empty body = null token)
- Frontend: `curl -sf http://localhost:5173 > /dev/null` → expect 200

### Backend Configuration

- The backend (Spring Boot) receives site key and secret as command-line args: `java -jar backend.jar --cap.site-key=xxx --cap.secret-key=yyy`.
- This overrides `application.properties` without needing temp config files.
- The frontend receives the site key via `VITE_CAP_SITE_KEY` environment variable, read by Vite at startup.

### Test Assertions

- All assertions are HTTP status-code only — no response body inspection.
- The backend's security posture (empty response bodies, no error detail leakage) is validated implicitly: every test asserts status code and confirms the body is empty.
- Playwright tests additionally assert: widget mounts, hidden token input appears (for widget modes), progress events fire, and the verification result component shows success.

### Site Key Registration

- The admin API requires session-based authentication: `POST /auth/login` with `admin_key` → receive session token → `POST /server/keys` with `Authorization: Bearer <base64-encoded JSON>` → receive `siteKey` and `secretKey`.
- The orchestration script performs this registration in Phase 1 and passes the credentials to the backend and frontend.

## Testing Decisions

### What makes a good test

- Tests exercise external behavior through HTTP requests and browser interactions — never implementation details.
- Tests are independent of each other at the phase level: Phase 2 produces tokens, Phases 3-4 consume them. Within Phase 2, each widget mode test is independent.
- Tests are deterministic given the service stack is healthy. The only timing-dependent test (expiry) uses a 10-second TTL with a 12-second wait, giving a comfortable margin.
- Redis is flushed after every full run to ensure a clean slate.

### Modules tested

- **Token TTL configurator**: Verified implicitly by the expiry test (12-second wait with 10-second TTL → 401).
- **Dual-mode compose**: Verified by the entire test stack running against standalone Redis.
- **Self-hosted asset chain**: Verified by all four Playwright tests with CDN hard-blocked. If WASM or widget.js fails to load from the Cap server, the PoW cannot complete and the test fails.
- **Backend verification**: Verified by all happy-path tests (200) and all failure tests (400, 401, 503).
- **Frontend integration**: Verified by all four Playwright tests across different widget modes.

### Prior art

- The existing unit tests in the backend (`CapControllerTest`, `CapVerificationServiceTest`) mock the service layer and HTTP client. The integration tests complement these by hitting real services.
- The existing 6 standalone integration tests exercise the Cap server's challenge/verify/replay routes directly. The new E2E tests extend coverage to include the browser → backend → Cap full stack.

## Out of Scope

- Containerizing the Vue frontend for testing (Playwright connects to Vite dev server directly)
- Containerizing the Spring Boot backend for testing (runs locally via Maven)
- Redis Cluster topology testing (the adapter code path difference is at connection setup only; all calling code is identical)
- Performance or load testing
- Testing the `cap.compat.min.js` widget build (only the standard widget is tested)
- Testing the `CAP_PAKO_URL` pako fallback (only relevant for very old browsers)
- Modifying the upstream widget JavaScript
- Adding `CONTEXT.md` or ADRs (this extends PRD 001's infrastructure work)
- Publishing Docker images to a registry

## Further Notes

- The Cap Docker image is built once and used for both production deployment (transferred as a tar archive) and integration testing. This ensures the test validates the exact artifact that will be deployed.
- The `TOKEN_TTL_MS` change is intentionally minimal (env var with upstream default) to maintain merge compatibility with the upstream repository.
- The test stack uses `redis-server` CLI already present on the host machine rather than a Valkey container, matching the production environment where Redis is managed externally.
- The wrong-secret test runs a second backend instance on port 8081. This avoids mid-test reconfiguration and makes the test deterministic.
- The CDN hard-block in Playwright (`page.route`) serves dual purposes: it proves assets are self-hosted, and it acts as a regression safety net if upstream widget code adds new CDN dependencies.
