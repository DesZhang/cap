# PRD: Cap Standalone — Redis Cluster Support, Key Prefixing, Self-Hosted Assets & Production Deployment

## Problem Statement

The standalone sub-project uses Bun's built-in `RedisClient`, which does not support Redis in cluster mode. Operators who run Redis Cluster (or Valkey Cluster) in production cannot deploy Cap standalone without replacing the Redis client. Additionally, the production environment has constraints that the upstream project does not address:

1. The Redis Cluster is shared by multiple services, requiring key namespace isolation.
2. End users may not have access to the default CDN (cdn.jsdelivr.net) due to corporate firewalls or regional restrictions.
3. The Cap server itself cannot make outbound requests to the CDN due to corporate firewall policies.
4. Downstream websites should not need to coordinate code changes when the Docker image is updated.

## Solution

Replace Bun's `RedisClient` with **ioredis** and introduce a production deployment pipeline that:

- Detects cluster vs standalone Redis via environment variables
- Prefixes all Redis keys with a configurable namespace (default `cap:`)
- Bakes widget and WASM assets into the Docker image at build time (fetched from CDN during build, not at runtime)
- Loads baked assets into Redis on container startup
- Serves all frontend assets from the Cap server itself — no CDN dependency for end users
- Provides a Chinese-language integration guide for downstream website operators

## User Stories

1. As a Cap operator, I want to point standalone at my Redis Cluster, so that I can deploy Cap in my existing cluster-mode Redis infrastructure.
2. As a Cap operator, I want standalone to keep working with a single Redis instance via `REDIS_URL`, so that my existing deployment does not break.
3. As a Cap operator, I want connection errors logged clearly, so that I can diagnose production Redis issues.
4. As a Cap operator, I want the adapter to auto-reconnect when Redis is temporarily unavailable, so that the service recovers without manual intervention.
5. As a Cap operator, I want auto-pipelining enabled, so that the Redis client batches commands for better throughput under load.
6. As a Cap operator, I want to authenticate to my cluster with a username and password, so that I can use secured Redis Cluster deployments.
7. As a Cap operator, I want cluster node URLs to be specified as a comma-separated list, so that configuration is simple and declarative.
8. As a Cap operator, I want to specify cluster node URLs in multiple formats (full URL, host:port, bare hostname), so that I can match whatever format my infrastructure provides.
9. As a Cap operator, I want all Redis keys prefixed with a namespace, so that my shared Redis Cluster does not have key collisions with other services.
10. As a Cap operator, I want to configure the key prefix via an environment variable, so that I can change it without rebuilding the image.
11. As a Cap developer, I want the Redis adapter change confined to a single module, so that merging upstream changes does not produce conflicts across the codebase.
12. As a Cap developer, I want the existing integration tests to pass unchanged, so that I have confidence the switch does not break functionality.
13. As a Cap developer, I want the test suite to skip gracefully when Redis is unavailable, so that CI does not hang or spam error output.
14. As a Cap operator, I want widget and WASM assets baked into the Docker image at build time, so that the server never needs outbound CDN access at runtime.
15. As a Cap operator, I want to specify widget and WASM versions as Docker build arguments, so that I control exactly which versions are deployed.
16. As a Cap operator, I want assets loaded into Redis automatically on container startup, so that the assets server routes serve them without CDN access.
17. As a Cap operator, I want the CDN fetcher to never attempt outbound requests, so that no firewall rules are needed for the Cap container.
18. As a Cap operator, I want a production Docker Compose file with safe default values pinned, so that I don't accidentally expose stack traces or disable the admin dashboard.
19. As a Cap operator, I want sensitive environment variables validated at container startup, so that misconfigured deployments fail fast with clear error messages.
20. As a downstream website developer, I want all frontend resources served from the Cap server, so that my users don't need CDN access.
21. As a downstream website developer, I want my website to automatically use the latest widget version when the Cap Docker image is updated, so that I don't need to change my HTML.
22. As a downstream website developer, I want a Chinese-language integration guide, so that I can correctly embed the Cap widget on my website.

## Implementation Decisions

### Redis Client

- **Client library:** ioredis v5.x. Chosen over node-redis (redis v4) because ioredis has more mature cluster handling, auto-pipelining support, transparent key prefixing, and a `send_command()` API that maps directly to Bun's `send()` for minimal diff.
- **Cluster detection:** A separate environment variable `REDIS_CLUSTER_URLS` (comma-separated node URLs). If set, the adapter creates a cluster instance. If not set, falls back to standalone using `REDIS_URL` / `VALKEY_URL`. Chosen over auto-detection (fragile, adds startup latency) and a boolean flag (requires operator to know topology ahead of time).
- **API compatibility:** The adapter attaches a `db.send` method that delegates to `send_command`, so all calling code using `db.send("SET", [...])` continues to work without changes.
- **`hgetall` normalisation:** The helper now calls `db.hgetall(key)` directly — ioredis returns an object by default, which the existing normaliser already handles.
- **Auto-pipelining:** `enableAutoPipelining: true` on both standalone and cluster connections. Batches all commands issued within a single event loop tick into a pipeline for improved throughput.
- **Connection lifecycle:** ioredis defaults for reconnection (exponential backoff, offline queue). All errors logged without filtering for production visibility. Startup `PING` check preserved.
- **Calling code untouched:** All files that import `db` (challenge handler, server, rate limiter, auth, settings cache, site verification, assets) remain identical to upstream.

### Key Prefixing

- **Mechanism:** ioredis built-in `keyPrefix` option. Automatically prepends the prefix to all keys in every command. Zero changes to calling code.
- **Default:** `cap:` — configurable via `REDIS_KEY_PREFIX` environment variable.
- **Caveat:** `keyPrefix` does not apply to `KEYS` or `SCAN` pattern arguments. The test cleanup code manually prepends the prefix when using `KEYS`.
- **Startup asset loader:** The asset loading script creates its own ioredis connection with the same `keyPrefix` so baked assets are stored under the correct namespace.

### Build-Time Asset Fetching

- **Approach:** A separate Docker build stage (`asset-fetcher`, based on `alpine:3.20` with curl) downloads widget JS, floating JS, WASM binary, and WASM loader from jsdelivr during `docker build`. Files are copied into the final image at `/usr/src/app/baked-assets/`.
- **Version control:** `CAP_WIDGET_VERSION` and `CAP_WASM_VERSION` are Docker build arguments with pinned defaults (currently widget@0.1.50, wasm@0.0.7). These are distinct from the upstream runtime env vars `WIDGET_VERSION` and `WASM_VERSION`, which only control the CDN→server fetcher.
- **Version metadata:** A `versions.json` file is written alongside the assets so the startup script knows what was baked.

### Startup Asset Loading

- **Mechanism:** A standalone script (`load-assets.js`) runs before the main app. It creates its own ioredis connection, reads the baked files, and writes them to Redis under the prefixed asset keys.
- **CDN re-fetch prevention:** The script writes `asset:cache-config` with `lastUpdate` set one year into the future. This prevents the upstream `updateCache()` function from ever attempting to re-fetch from CDN. Since `ENABLE_ASSETS_SERVER` is not set, the fetcher returns immediately anyway — this is defense in depth.
- **Entrypoint:** A shell wrapper (`entrypoint.sh`) runs the asset loader first, then execs the main app. This replaces the upstream `ENTRYPOINT ["bun", "run", "./src/index.js"]`.

### Assets Server Behavior

- **`ENABLE_ASSETS_SERVER`:** Not set in production. The upstream CDN fetcher is a no-op. The `/assets/*` routes are always registered regardless of this flag and serve from Redis.
- **Self-hosted resource chain:** Website operators load `widget.js` from `/assets/widget.js`. The widget loads WASM from the URL specified by `window.CAP_CUSTOM_WASM_URL`, which points to `/assets/cap_wasm_bg.wasm` on the same server. No external CDN access required by the end user's browser.
- **Seamless upgrades:** When the Docker image is rebuilt with new widget/WASM versions, the Cap server serves the new versions. Website HTML does not need to change.

### Production Docker Compose

- **Separate file:** `docker-compose.cluster.yml` — builds from source, no embedded Valkey, points to external Redis Cluster. Upstream `docker-compose.yml` stays untouched.
- **Build args:** `CAP_WIDGET_VERSION` and `CAP_WASM_VERSION` are declared with pinned defaults.
- **Safe value pinning:** `SHOW_ERRORS=false`, `DISABLE_ERROR_LOGGING=false`, `DEMO_MODE=false` are explicitly set with inline comments explaining each. Defense in depth against accidental misconfiguration.
- **Required variable validation:** `ADMIN_KEY`, `REDIS_CLUSTER_URLS`, `REDIS_CLUSTER_PASSWORD` use Docker Compose required-variable syntax (`${VAR:?message}`) so the container fails immediately with a clear error if any are missing.
- **Reverse proxy support:** `RATELIMIT_IP_HEADER` defaults to `X-Forwarded-For`.

### Integration Guide

- **Language:** Chinese (Simplified).
- **Contents:** Quick start, full HTML examples (basic and floating-button mode), widget attribute reference, `CAP_CUSTOM_WASM_URL` explanation, upgrade notes, FAQ covering CDN-free operation, multi-site usage, and token expiry.

## Testing Decisions

- **What makes a good test:** The existing integration tests exercise external behaviour through HTTP requests against the Elysia app — challenge issuance, solution validation, replay rejection, scope mismatch, and 404 for unknown keys. They do not test implementation details of the Redis adapter or asset loading.
- **Key prefix verification:** Verified by inspecting Redis directly after test runs — all keys carry the `cap:` prefix, zero unprefixed keys.
- **Modules tested:** The integration tests exercise the full request path through all Redis-dependent modules via the real adapter with `keyPrefix` enabled.
- **Prior art:** The existing 6 tests in the standalone test suite serve as acceptance criteria. All 6 pass with the ioredis adapter and key prefixing against a real Redis instance.
- **Asset loading:** The startup script is tested manually — it connects, writes, and logs the loaded versions. The assets server routes are tested by the existing route handlers reading from Redis.

## Out of Scope

- Cluster-mode integration test (would require a real multi-node Redis Cluster in CI)
- Replacing raw `db.send()` calls with ioredis first-class methods (intentionally kept for merge compat)
- Replacing `KEYS` command in test cleanup with `SCAN`
- Modifying the upstream `docker-compose.yml` or `docker-compose.dev.yml`
- Patching the widget JS to hardcode the WASM URL (chosen `CAP_CUSTOM_WASM_URL` approach instead)
- Adding `CONTEXT.md` or ADRs (this is a focused infrastructure change, not a domain-level decision)
- Performance benchmarks comparing Bun's RedisClient vs ioredis
- Self-hosting the `pako` decompression library (only needed as a fallback for very old browsers)
- Docker image publishing to a registry (build-from-source approach chosen for now)

## Further Notes

- The `REDIS_CLUSTER_URLS` variable name was chosen over `REDIS_NODES` to be explicit that these are URLs, not just hostnames.
- `CAP_WIDGET_VERSION` and `CAP_WASM_VERSION` are intentionally separate from the upstream `WIDGET_VERSION` and `WASM_VERSION` env vars. The upstream vars only control the CDN→server fetcher (which is disabled). The new vars are build-time only and control what gets baked into the image.
- ioredis's `keyPrefix` does not apply to `KEYS` or `SCAN` pattern arguments — this is documented in ioredis's README and handled in the test cleanup.
- ioredis's built-in `getBuffer()` returns a Node.js Buffer, which Bun handles natively — no conversion needed for the WASM asset serving.
- This change was designed so that merging upstream changes to challenge handler, server, rate limiter, auth, and other calling-code files produces zero conflicts. Only the Redis adapter module diverges from upstream.
- The Dockerfile change (new `asset-fetcher` build stage + entrypoint wrapper) is the most merge-sensitive file since upstream may update the Dockerfile. The asset-fetcher stage is a separate build stage that can be easily rebased.
