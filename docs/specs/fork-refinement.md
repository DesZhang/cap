# Spec: Fork Refinement — Release, Structure, Upstream Sync

Date: 2025-09-16
Branch: `feat/redis-cluster-mode` (fork: DesZhang/cap, upstream: tiagozip/cap)

## Goals

1. **Release**: one non-interactive command from code to offline deployment bundle.
2. **Structure**: make fork-owned vs upstream-owned layout obvious; relocate misplaced pieces.
3. **Upstream sync**: a repeatable workflow to pull useful upstream updates into the feat branch while keeping it stable.

## Decisions

### D1 — `offline/` moves to top level ✅

`standalone/offline/` → `offline/`. Convention: **fork-owned additions live at top level; upstream directories only contain unavoidable in-place modifications** (e.g. `standalone/src/db.js` ioredis switch, `standalone/Dockerfile` asset baking). This makes "what's ours" visible at a glance and keeps `standalone/` recognizable as upstream's package.

Cost accepted: path updates inside `build-package.sh`, `deploy-local.sh`, `smoke-test.sh`, `verify.sh`, Dockerfile `-f` references. No merge risk either way.

**Naming**: the directory keeps the name `offline/` — it matches the glossary term (Offline Package) and every emitted artifact (`cap-offline:{version}` image, `cap-offline-{version}.tar.gz`, 离线 guides). `packaging/` was considered and rejected: vocabulary split for zero functional gain. Cheap to reverse if ever needed.

### D2 — e2e fixtures move under `e2e/` ✅

`frontend/` → `e2e/fixtures/frontend`, `backend/` → `e2e/fixtures/backend`. Both exist solely as integration-test fixtures consumed by `run-e2e.sh`; they stop masquerading as first-class deployment packages. `run-e2e.sh` and `.gitignore` paths updated accordingly.

### D3 — `main` is a pure mirror of `upstream/main` ✅

No fork commits ever land on `main`. Sync = reset `main` to `upstream/main` (handles upstream force-pushes, e.g. the one already observed). The fork's only product branch is `feat/redis-cluster-mode`.

### D4 — Upstream updates reach the feat branch by merge, never rebase ✅

`git merge main` into `feat/redis-cluster-mode`. The branch is pushed and long-lived; rebasing rewrites shared history. Merge commits double as a record of when each upstream sync happened.

### D5 — Merge gate = `run-e2e.sh` + full `build-package.sh` ✅

A merged feat branch is only pushed after the full e2e suite AND the offline package build (which includes the smoke test) pass. Rationale: the known weak point is `apply-patches.js` regex patches silently breaking on upstream refactors — only these heavyweight runs actually exercise them.

### D6 — Offline package version = `standalone/package.json` version ✅

Keep as is. Rebuilds of the same base version overwrite the tar.gz. Add a `+n` suffix only when distinguishing rebuilds becomes a real need.

### D7 — Offline customizations become real source modifications ✅

Swagger removal, `BASE_PATH` prefix (default `""` = upstream parity), and ipdb auto-detect move from build-time regex patches (`apply-patches.js`) into `standalone/src/` directly. `apply-patches.js` and the patch stage in `Dockerfile.offline` are deleted; the maintenance-warning ceremony leaves `build-package.sh`. Consequences accepted: mods apply to every image built from the branch (e2e image loses swagger — harmless; BASE_PATH/ipdb no-op when unset/absent); upstream merges now **conflict visibly** where they used to **drift silently** (regex mismatch only `console.warn`ed). Supersedes PRD 003's "source identical to upstream" goal. See ADR 0001.

### D8 — Merge executor is the agent, driven by FORK.md; no bespoke merge script ✅

`FORK.md` at repo root holds: the layout rule (D1), the deviation list with intent (D7), the release command, and a human-executable merge runbook (fetch → reset mirror `main` → merge into feat → gate → review → manual push). The agent is the usual executor (it handles the hard 10%: semantic conflicts, force-pushes, regex-era leftovers are gone by D7); the runbook is the no-agent fallback. D5 gate unchanged; push stays manual.

### D9 — Release entry point: `offline/build-package.sh`, no wrapper ✅

One command, non-interactive (the `read -p` confirm and the patch-maintenance warnings are deleted with D7). No root `release.sh`/Makefile wrapper. Fork conventions documented in `FORK.md`, not in upstream's `README.md`.

## Implementation Checklist — ✅ executed 2025-09-16

All items done, full gate passed (`bun test` + import check, `run-e2e.sh` 4/4 Playwright + 7/7 API tests, `offline/build-package.sh` smoke 8/8 + `cap-offline-3.1.0.tar.gz` 128M produced, non-interactive).

1. `git mv standalone/offline offline/` — update internal path math (`build-package.sh`, `deploy-local.sh`, `smoke-test.sh`, `verify.sh`, `docker-compose.test.yml`, `Dockerfile.offline -f` references).
2. `git mv frontend e2e/fixtures/frontend`, `git mv backend e2e/fixtures/backend` — update `run-e2e.sh` and `.gitignore` paths.
3. Apply the three patches as real mods in `standalone/src/index.js`, `standalone/src/ipdb.js`, `standalone/package.json` (+ regenerate `bun.lock`); delete `offline/scripts/apply-patches.js`; simplify `Dockerfile.offline` (drop patch stage + swagger sed). ✅ Also fixed latent bug: `smoke-test.sh` version fallback pointed at a nonexistent `package.json`; and made the shipped-compose version sed version-agnostic.
4. Make `build-package.sh` non-interactive; drop maintenance-warning ceremony.
5. Write `FORK.md` (layout rule, deviation list, release command, merge runbook, gate).
6. Full gate: `bun test` (standalone), `run-e2e.sh`, `offline/build-package.sh`.
