# Cap Fork (DesZhang/cap)

Fork of tiagozip/cap maintained for Redis Cluster support and an air-gapped production deployment. The fork carries its changes on one product branch; upstream structure is kept mergeable.

## Language

**Upstream**:
The original tiagozip/cap repository, source of periodic updates.
_Avoid_: origin (that's our fork's remote)

**Fork Branch**:
`feat/redis-cluster-mode` — the fork's only product branch; everything we ship derives from it.

**Mirror Main**:
Our `main`, a pure fast-forward/reset mirror of `upstream/main`. Never carries fork commits.

**Offline Package**:
The self-contained air-gapped deployment bundle (`cap-offline-{version}.tar.gz`): Docker image with baked assets and geo DB, compose file, env template, verification scripts, Chinese guides.
_Avoid_: release bundle, custom release

**Fork Deviations**:
The intentional source modifications this branch carries versus upstream (ioredis Redis adapter, self-hosted assets, configurable token TTL, swagger removal, `BASE_PATH` prefix, IP DB auto-detect). Documented with intent in `FORK.md`; visible via `git diff main..feat/redis-cluster-mode`.
_Avoid_: build-time patches, source patches

**Merge Runbook**:
The human-executable upstream-sync procedure in `FORK.md`: fetch → reset mirror `main` → merge into the Fork Branch → run the Merge Gate → review → push. Usually executed by the agent; the runbook is the no-agent fallback.

**Integration Fixtures**:
The demo frontend (Vue) and demo backend (Spring Boot) that `run-e2e.sh` drives Playwright against. Test doubles, not deployment packages.
_Avoid_: demo apps, reference apps

**Merge Gate**:
The checks a merged Fork Branch must pass before push: full `run-e2e.sh` plus a complete offline package build.
