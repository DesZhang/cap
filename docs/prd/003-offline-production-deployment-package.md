# PRD: Cap Offline Production Deployment Package

## Problem Statement

As an ops team deploying Cap (a proof-of-work CAPTCHA alternative) into an air-gapped production environment with no outbound internet access, I need a self-contained deployment package that includes the Docker image, configuration, Chinese documentation, and verification tooling — so that I can deploy, integrate, and verify Cap without any dependency on external CDN or internet resources.

## Solution

Create an offline deployment package build pipeline under `standalone/offline/` that produces a versioned `.tar.gz` archive. The package contains a pre-built Docker image with upstream code patches applied at build time (swagger removal, configurable API prefix, pre-bundled geo DB), a production docker-compose targeting an existing Redis cluster, Chinese deploy and integration guides, and automated verification scripts.

The build pipeline minimizes upstream code divergence by applying all customizations as Docker build-time patches — the source repository stays identical to upstream, reducing merge friction to near zero.

## User Stories

### Build & Package

1. As a release engineer, I want to run a single shell script that produces a versioned `.tar.gz` offline package, so that I can deliver it to the ops team without manual steps.
2. As a release engineer, I want the build script to read the version from `standalone/package.json` and pin the Docker image tag to that version, so that the offline package stays aligned with upstream releases.
3. As a release engineer, I want the build script to automatically run a local smoke test after building the image, so that broken packages are never shipped.
4. As a release engineer, I want a `--skip-test` flag on the build script, so that I can iterate quickly during development.
5. As a release engineer, I want the build script to warn me that sed patterns for swagger stripping need review after upstream merges, so that I do not silently ship swagger endpoints to production.
6. As a release engineer, I want the build to target `linux/amd64` only by default, so that the image is optimized for our production servers.
7. As a release engineer, I want the build to produce a single `cap-offline-{version}.tar.gz` file, so that transfer to the air-gapped environment is straightforward.

### Docker Image

8. As an ops engineer, I want the Docker image to have all widget JS, WASM, and floating.js assets baked in, so that no CDN access is needed at runtime.
9. As an ops engineer, I want the Docker image to have DB-IP geo databases (country + ASN) pre-bundled, so that geo analytics and country/ASN filtering work without internet.
10. As an ops engineer, I want the Docker image to have swagger completely removed, so that no API explorer surface is exposed in production.
11. As an ops engineer, I want all API routes prefixed with `/cap` (configurable via `BASE_PATH` env var), so that reverse proxy configuration is a single `location /cap/` rule.
12. As an ops engineer, I want the IP geolocation database to auto-activate on first start when `.mmdb` files are found on disk, so that geo features work without manual configuration.
13. As an ops engineer, I want the IP DB auto-detection to respect any admin override from the dashboard, so that humans can always change the mode later.

### Deployment

14. As an ops engineer, I want a production docker-compose that references the pre-built image (no `build:` directive), so that no source code is needed on the production server.
15. As an ops engineer, I want the docker-compose to connect to our existing Redis cluster (no bundled Valkey service), so that we use our managed infrastructure.
16. As an ops engineer, I want all configuration driven by a `.env` file with clear documentation, so that I can configure without editing YAML.
17. As an ops engineer, I want a `.env.example` template listing all required and optional variables with descriptions, so that I know exactly what to configure.

### Verification

18. As an ops engineer, I want a `verify.sh` script that checks the full deployment health (image loaded, Redis reachable, container started, assets served offline, challenge API responds, geo DB loaded, dashboard accessible), so that I can confidently confirm the deployment works.
19. As an ops engineer, I want the build-time smoke test to reuse an existing Redis container if one is already running, so that the test is fast and does not create conflicts.
20. As an ops engineer, I want the smoke test to verify assets are served from the Cap server (not CDN), so that offline operation is confirmed before shipping.

### Documentation

21. As an ops engineer, I want a Chinese deploy guide covering prerequisites, transfer, image load, configuration, startup, verification, upgrade, and troubleshooting, so that my team can deploy without English proficiency.
22. As an ops engineer, I want the deploy guide to clearly separate public-facing APIs from internal-only APIs, so that I can configure network policies and reverse proxy rules correctly.
23. As an ops engineer, I want the deploy guide to list the exact API paths under `/cap/` for both public and internal categories, so that there is no ambiguity about the network boundary.
24. As a website developer, I want a Chinese integration guide showing exactly how to add Cap to my website with the `/cap` prefix on all routes, so that I can integrate without guessing URLs.
25. As a website developer, I want the integration guide to explain that all resources come from the Cap server and no external CDN is needed, so that I understand the offline architecture.

## Implementation Decisions

### Module: Dockerfile.offline

A custom Dockerfile extending the upstream build pattern with three build-time patches and geo DB bundling.

- **Base build**: Follows the same multi-stage pattern as the upstream `standalone/Dockerfile` (oven/bun:slim, dev/prod install stages, asset-fetcher stage).
- **Swagger stripping**: Applied via `sed` during build. Removes the import of `@elysiajs/swagger`, the `.use(swagger({...}))` block from `index.js`, and the dependency from `package.json`. This is fragile — the build script includes a maintenance warning that sed patterns must be reviewed after upstream merges.
- **BASE_PATH injection**: Patches `index.js` to read `process.env.BASE_PATH` and inject it as Elysia `prefix`. Default is empty string (no prefix, upstream behavior). The offline compose sets `BASE_PATH=/cap`.
- **IP DB auto-detection**: Patches `loadIPDB()` in `ipdb.js` to add a fallback path: if no `settings:ipdb` exists in Redis but `.mmdb` files exist on disk, auto-set mode to `dbip` and open the readers. Only activates on first start; admin dashboard overrides take precedence afterward.
- **Geo DB download**: A new build stage downloads the current month's DB-IP free databases (country-lite + asn-lite, CC-BY 4.0 license) from `download.db-ip.com` and bakes them into the image at `/usr/src/app/data/`.
- **Architecture**: `linux/amd64` only (matching production servers).

### Module: build-package.sh

Orchestrator script at `standalone/offline/build-package.sh`.

- Reads version from `standalone/package.json` (currently `3.1.0`) and tags the image as `cap-offline:{version}`.
- Builds via `Dockerfile.offline` with context set to repo root.
- After build, runs local smoke test by default (uses `docker-compose.test.yml` with a single Redis container). Supports `--skip-test`.
- Reuses existing Redis container if already running on the test port.
- Assembles the final `cap-offline-{version}.tar.gz` containing: image tar, docker-compose.yml, .env.example, verify.sh, deploy-guide.md, integration-guide.md, LICENSE.
- Includes commented maintenance warnings about fragile sed patterns for swagger, BASE_PATH, and ipdb patches.

### Module: docker-compose.yml (production)

Offline-specific compose at `standalone/offline/docker-compose.yml`.

- Single `cap` service with `image: cap-offline:{version}` (no `build:` directive).
- No Valkey/Redis service — connects to existing Redis cluster via `REDIS_CLUSTER_URLS` env var.
- `BASE_PATH` defaults to `/cap`.
- All other env vars mirror upstream `docker-compose.cluster.yml` conventions (ADMIN_KEY required, SHOW_ERRORS/DISABLE_ERROR_LOGGING/DEMO_MODE pinned to safe production values).

### Module: docker-compose.test.yml

Lightweight compose for build-time smoke test.

- Runs the `cap-offline` image with a single `redis` service (no cluster, standalone mode).
- Uses a non-standard host port (e.g. 13000) to avoid conflicts with any local Cap instance.
- The Redis container is reused across builds if already running.

### Module: smoke-test.sh

Local smoke test script that runs during `build-package.sh`.

- Loads the freshly built image.
- Starts test compose (or reuses existing Redis).
- Waits for container health.
- Verifies: widget.js served from `/cap/assets/widget.js`, WASM served, challenge API responds, geo DB is loaded (check container logs).
- Tears down test containers (keeps Redis if it was already running).
- Exits non-zero on any failure.

### Module: verify.sh

Production health check script shipped inside the package.

- Step 1: Confirm `cap-offline:{version}` image exists via `docker images`.
- Step 2: Ping Redis cluster at `REDIS_CLUSTER_URLS`.
- Step 3: Start containers via `docker compose up -d`, wait for health.
- Step 4: Curl widget.js, floating.js, WASM from `/cap/assets/*` — confirm no CDN dependency.
- Step 5: Create a challenge via `POST /cap/{siteKey}/challenge` — confirm API responds.
- Step 6: Check container logs for `[ipdb]` success message or call geo-stats endpoint.
- Step 7: Confirm admin dashboard responds at `/cap/` with ADMIN_KEY auth.
- Outputs pass/fail for each step with clear Chinese-language messages.

### Module: deploy-guide.md

Chinese deploy guide covering:

- Prerequisites (Docker, running Redis cluster, server specs).
- Transfer `.tar.gz` to production server.
- `docker load < cap-image.tar`.
- Configure `.env` with explanations for each variable and examples.
- `docker compose up -d`.
- Run `bash verify.sh`.
- API boundary section with two tables:
  - Public APIs (downstream websites + user browsers): `/cap/{siteKey}/challenge`, `/cap/{siteKey}/redeem`, `/cap/{siteKey}/siteverify`, `/cap/assets/*`.
  - Internal APIs (admin dashboard, requires auth): `/cap/auth/*`, `/cap/server/keys/*`, `/cap/server/settings/*`, `/cap/server/ipdb/*`, `/cap/server/*/blocked-ips`.
- Network recommendation: restrict `/cap/server/*` and `/cap/auth/*` to internal network at reverse proxy layer.
- Upgrade process (new package → load image → restart).
- Troubleshooting (Redis unreachable, port conflicts, geo DB not loading).

### Module: integration-guide.md

Chinese website integration guide adapted from existing `INTEGRATION-ZH.md` with all paths prefixed by `/cap`.

- Script tags point to Cap server: `https://cap.example.com/cap/assets/widget.js`.
- WASM URL: `https://cap.example.com/cap/assets/cap_wasm_bg.wasm`.
- Widget config: `data-cap-api-endpoint="https://cap.example.com/cap"`.
- Backend siteverify: `POST https://cap.example.com/cap/{siteKey}/siteverify`.
- Explains that all resources come from Cap server, no CDN needed.
- Configuration parameters table (same as INTEGRATION-ZH.md but with `/cap` paths).

### Module: .env.example

Template file with all required and optional env vars, commented with descriptions in Chinese.

- `ADMIN_KEY` (required)
- `REDIS_CLUSTER_URLS` (required)
- `REDIS_CLUSTER_PASSWORD` (optional)
- `REDIS_CLUSTER_USERNAME` (optional)
- `REDIS_KEY_PREFIX` (optional, default `cap:`)
- `TOKEN_TTL_MS` (optional)
- `RATELIMIT_IP_HEADER` (optional, default `X-Forwarded-For`)
- `BASE_PATH` (default `/cap`)
- `CAP_PORT` (host port mapping, default `3000`)

### Patch Strategy (cross-cutting)

All customizations are build-time patches applied by `sed` inside `Dockerfile.offline`. Source files in the repo are never modified. This means:

- Zero merge conflicts with upstream.
- Three fragile patches need manual review after each merge: swagger stripping patterns, BASE_PATH injection point in `index.js`, ipdb auto-detection logic in `ipdb.js`.
- If upstream adds swagger to additional files, the build script maintenance warning prompts review.

## Testing Decisions

### What makes a good test

Tests verify external behavior (HTTP responses, container health, asset availability) without asserting on internal implementation details. This makes tests resilient to upstream code changes.

### Modules tested

- **smoke-test.sh**: Tests the built Docker image locally during build. Verifies asset serving, challenge API, geo DB activation. Runs inside `build-package.sh` by default.
- **verify.sh**: Tests the deployed service in production. Seven discrete checks with pass/fail output.

### Prior art

No existing test infrastructure for the standalone server beyond `bun test` for unit tests. The smoke test and verify scripts are greenfield additions that operate at the HTTP/container level — no framework dependencies.

## Out of Scope

- Upstream source code modifications (all changes are build-time patches).
- TLS/HTTPS termination configuration (reverse proxy responsibility).
- Docker installation on production servers.
- Redis cluster setup or management.
- CI/CD pipeline integration for automated package builds.
- ARM64 architecture support (amd64 only for now).
- Submitting BASE_PATH or IP DB auto-detection features upstream as PRs (may do later).
- Translating documentation to English (Chinese only per requirement).

## Further Notes

### Version alignment

The offline package version is always pinned to the upstream `standalone/package.json` version (currently `3.1.0`). When merging upstream updates, the release engineer runs `build-package.sh` and the version tag propagates automatically. This ensures the offline package is always traceable to an upstream release.

### DB-IP license

The DB-IP free databases (Country Lite + ASN Lite) are licensed under CC-BY 4.0. The deploy guide should note the attribution requirement. The databases are downloaded during `docker build` on the internet-connected builder machine and baked into the image.

### Future considerations

- If upstream adds their own `BASE_PATH` or prefix support, the build-time patch can be dropped.
- If upstream changes the swagger integration significantly, the sed patterns need updating — the build script warns about this.
- ARM64 support can be added by passing `--platform linux/arm64` or building multi-platform with `docker buildx`.
