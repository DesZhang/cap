# Fork Guide (DesZhang/cap)

This fork adapts [tiagozip/cap](https://github.com/tiagozip/cap) for production
use behind a corporate firewall: Redis Cluster, key prefixing, self-hosted
assets, and an air-gapped deployment package. Everything an engineer (or an AI
agent) needs to maintain this fork lives here.

## Layout rule

**Fork-owned additions live at top level; upstream directories contain only
unavoidable in-place modifications.**

| Path | Owner | What it is |
|---|---|---|
| `offline/` | fork | Offline Package workflow: build, smoke test, package, local deploy, shipped ops docs |
| `e2e/` (+ `e2e/fixtures/`) | fork | Playwright integration suite + demo frontend/backend fixtures driven by `run-e2e.sh` |
| `docs/prd/`, `docs/specs/`, `docs/adr/`, `CONTEXT.md` | fork | Design history |
| `standalone/`, `core/`, `widget/`, `wasm/`, `demo/`, `docs/` | upstream | Upstream packages — only `standalone/` carries modifications (below) |

## Fork deviations in `standalone/`

Intent, so a merge (human or agent) can re-apply it after upstream refactors:

1. **`src/db.js`** — ioredis replaces Bun's `RedisClient` (upstream lacks
   cluster mode). Dual mode: `REDIS_CLUSTER_URLS` (comma-separated nodes, may
   carry user/password) or `REDIS_URL`/`VALKEY_URL`. `REDIS_KEY_PREFIX`
   namespaces all keys in the shared cluster. Auto-pipelining on. `db.send`
   shim keeps upstream calling code unchanged.
2. **`src/index.js`** — swagger API explorer removed (production surface);
   `prefix: process.env.BASE_PATH || ""` on the Elysia constructor so all
   routes can sit under one reverse-proxy path (default `""` = upstream
   behavior).
3. **`src/ipdb.js`** — on first start with no `settings:ipdb` in Redis and
   pre-bundled `.mmdb` files present (offline image), auto-persists mode
   `dbip`. Dashboard overrides always win afterwards.
4. **`src/cap.js`** — `TOKEN_TTL_MS` env override for token expiry (default
   2h, upstream hardcodes).
5. **`src/static.js`, assets loading** — widget/WASM/floating assets are
   baked into the image at build time (`asset-fetcher` Docker stage, versions
   pinned via `CAP_WIDGET_VERSION`/`CAP_WASM_VERSION` build args) and served
   by Cap itself; no CDN dependency for end users or the server.
6. **`package.json`/`bun.lock`** — adds `ioredis`; no `@elysiajs/swagger`.

## Release (Offline Package)

One command, non-interactive, from clean tree to deployment bundle:

```bash
bash offline/build-package.sh            # build → smoke test → cap-offline-<version>.tar.gz
bash offline/build-package.sh --skip-test
```

Version comes from `standalone/package.json` (upstream's version). The bundle
contains the image tar, compose file, `.env.example`, `verify.sh`, and Chinese
deploy/integration guides. Local try-before-ship: `offline/deploy-local.sh`,
teardown `offline/cleanup-local.sh`.

## Upstream sync (merge runbook)

`main` is a **pure mirror** of `upstream/main` — never commit to it. The
product branch is `feat/redis-cluster-mode`. Sync by **merge, never rebase**
(the branch is pushed and long-lived).

```bash
git fetch upstream
git checkout main && git reset --hard upstream/main   # mirror, survives force-pushes
git checkout feat/redis-cluster-mode
git merge main
# resolve conflicts using the deviation list above (intent, not line-matching)
```

**Merge gate — push only after all of this passes:**

```bash
cd standalone && bun test && cd ..
./run-e2e.sh                    # full stack: cluster Redis, Java backend, Vue frontend
bash offline/build-package.sh   # includes the offline smoke test
```

Then review `git diff @{u}` and push manually.

When merging, watch for: swagger reintroduced in new files or the constructor
shape changing (`prefix` injection), `loadIPDB()` control flow changing
(auto-detect block), `db.js` calling-convention drift, and widget/WASM
version pins vs new upstream releases.

## Glossary & history

Domain terms: `CONTEXT.md`. Decisions: `docs/adr/`, `docs/specs/`. Original
requirements: `docs/prd/` (note: PRD 003's build-time patch approach is
superseded by ADR 0001).
