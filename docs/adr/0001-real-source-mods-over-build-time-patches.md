# Real source modifications over build-time regex patches

Status: accepted (supersedes the patch approach in `docs/prd/003-offline-production-deployment-package.md`)

The fork originally kept `standalone/src/` byte-identical to upstream and applied its offline-flavor customizations (swagger removal, `BASE_PATH` prefix, IP DB auto-detect) as regex patches inside the Docker build (`offline/scripts/apply-patches.js`, formerly `standalone/offline/scripts/`), to minimize git merge friction when syncing upstream.

We reversed that: the customizations now live as ordinary source modifications on the feat branch, and the patcher is deleted. The regex approach only `console.warn`ed when upstream refactors broke a pattern — silent drift, discovered (at best) by the smoke test. Real modifications make upstream changes **conflict visibly in git**, where the doc-driven merge workflow (see `FORK.md`) resolves them semantically; they also deleted the most fragile, most ceremonious part of the release path.

Consequence: modifications apply to every image built from this branch (including the e2e image, which loses swagger — harmless; `BASE_PATH` defaults to `""` and ipdb auto-detect no-ops without pre-bundled `.mmdb` files, so upstream behavior is preserved when unset).
