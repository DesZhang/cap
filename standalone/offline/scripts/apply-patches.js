/**
 * apply-patches.js — Build-time patches for Cap offline Docker image.
 *
 * Applied inside the Dockerfile.offline prerelease stage.
 * Source files in the repo are NEVER modified — only the copies inside the image.
 *
 * Patches applied:
 *   1. Remove swagger import and .use() block from index.js
 *   2. Inject BASE_PATH env var as Elysia prefix in index.js
 *   3. Add IP DB auto-detection fallback in ipdb.js
 *   4. Remove @elysiajs/swagger from package.json
 *
 * ⚠️ MAINTENANCE NOTE:
 * These patches use regex matching against specific upstream code patterns.
 * After each upstream merge, review:
 *   - Has swagger been added to other files?
 *   - Has the index.js Elysia constructor changed?
 *   - Has ipdb.js loadIPDB() early-return logic changed?
 * Adjust the patterns below if needed.
 */

import { readFileSync, writeFileSync } from "node:fs";

// ── Patch 1 & 2: index.js (swagger removal + BASE_PATH injection) ──

let index = readFileSync("src/index.js", "utf-8");

// Remove swagger import
const swaggerImport = /import \{ swagger \} from "@elysiajs\/swagger";\n/;
if (!swaggerImport.test(index)) {
  console.warn("[patch] WARN: swagger import not found in index.js — upstream may have changed");
}
index = index.replace(swaggerImport, "");

// Remove swagger .use() block
const swaggerUse = /\n\s*\.use\(\s*\n\s*swagger\(\{[\s\S]*?\n\s*\}\),\s*\n\s*\)/;
if (!swaggerUse.test(index)) {
  console.warn("[patch] WARN: swagger .use() block not found in index.js — upstream may have changed");
}
index = index.replace(swaggerUse, "");

// Inject BASE_PATH as Elysia prefix
const elysiaCtor = /new Elysia\(\{\s*\n(\s*)serve:/;
if (!elysiaCtor.test(index)) {
  console.warn("[patch] WARN: Elysia constructor pattern not found in index.js — upstream may have changed");
}
index = index.replace(
  elysiaCtor,
  'new Elysia({\n  prefix: process.env.BASE_PATH || "",\n$1serve:'
);

writeFileSync("src/index.js", index);
console.log("[patch] index.js: swagger removed, BASE_PATH injected");

// ── Patch 3: ipdb.js (auto-detection fallback) ──

let ipdb = readFileSync("src/ipdb.js", "utf-8");

const earlyReturn = /if \(!ipdbSettings\?\.mode \|\| ipdbSettings\.mode === "ipinfo"\) return;/;
if (!earlyReturn.test(ipdb)) {
  console.warn("[patch] WARN: ipdb early-return pattern not found — upstream may have changed");
}
ipdb = ipdb.replace(
  earlyReturn,
  `if (!ipdbSettings?.mode || ipdbSettings.mode === "ipinfo") {
    // [offline-patch] Auto-detect pre-bundled .mmdb files when no Redis settings exist
    if (existsSync(COUNTRY_PATH) || existsSync(ASN_PATH)) {
      console.log("[ipdb] No settings in Redis — auto-detecting pre-bundled .mmdb files");
      ipdbSettings = {
        mode: "dbip",
        maxmindKey: "",
        ipinfoToken: "",
        lastUpdated: new Date().toISOString(),
      };
      try { await db.set("settings:ipdb", JSON.stringify(ipdbSettings)); } catch {}
    } else {
      return;
    }
  }`
);

writeFileSync("src/ipdb.js", ipdb);
console.log("[patch] ipdb.js: auto-detection fallback added");

// ── Patch 4: package.json (remove swagger dependency) ──

let pkg = readFileSync("package.json", "utf-8");
const swaggerDep = /"@elysiajs\/swagger": "[^"]+",?\n/;
if (!swaggerDep.test(pkg)) {
  console.warn("[patch] WARN: @elysiajs/swagger not found in package.json — already removed?");
}
pkg = pkg.replace(swaggerDep, "");
writeFileSync("package.json", pkg);
console.log("[patch] package.json: @elysiajs/swagger removed");

console.log("[patch] All patches applied successfully");
