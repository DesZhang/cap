#!/usr/bin/env bun
/**
 * load-assets.js — Load baked-in widget + WASM assets into Redis.
 *
 * Run once at container startup before the main app starts.
 * This script is designed to be called from a wrapper entrypoint.
 *
 * It reads files from /usr/src/app/baked-assets/ (baked into the
 * Docker image at build time) and writes them to Redis using the
 * same keys the assets server reads from.
 *
 * Because ioredis is configured with keyPrefix="cap:", all keys
 * written here are automatically prefixed.
 */

import Redis from "ioredis";
import { readFileSync } from "node:fs";

const ASSETS_DIR = process.env.BAKED_ASSETS_DIR || "/usr/src/app/baked-assets";

const redisUrl =
  process.env.REDIS_URL || process.env.VALKEY_URL || "redis://localhost:6379";
const clusterUrls = process.env.REDIS_CLUSTER_URLS;
const keyPrefix = process.env.REDIS_KEY_PREFIX || "cap:";

const commonOptions = {
  enableAutoPipelining: false,
  lazyConnect: true,
  keyPrefix,
};

let db;

if (clusterUrls) {
  const nodes = clusterUrls.split(",").map((url) => {
    const trimmed = url.trim();
    if (trimmed.includes("://")) {
      const parsed = new URL(trimmed);
      return { host: parsed.hostname, port: Number(parsed.port) || 6379 };
    }
    if (trimmed.includes(":")) {
      const [host, port] = trimmed.split(":");
      return { host, port: Number(port) || 6379 };
    }
    return { host: trimmed, port: 6379 };
  });

  db = new Redis.Cluster(nodes, {
    redisOptions: {
      ...commonOptions,
      username: process.env.REDIS_CLUSTER_USERNAME || undefined,
      password: process.env.REDIS_CLUSTER_PASSWORD || undefined,
    },
  });
} else {
  db = new Redis(redisUrl, commonOptions);
}

db.on("error", (err) => {
  console.error("[load-assets] Redis error:", err.message);
});

async function loadAssets() {
  await db.connect();

  const versions = JSON.parse(
    readFileSync(`${ASSETS_DIR}/versions.json`, "utf-8"),
  );

  const widgetJs = readFileSync(`${ASSETS_DIR}/widget.js`, "utf-8");
  const floatingJs = readFileSync(`${ASSETS_DIR}/floating.js`, "utf-8");
  const wasmBinary = readFileSync(`${ASSETS_DIR}/cap_wasm_bg.wasm`);
  const wasmJs = readFileSync(`${ASSETS_DIR}/cap_wasm.js`, "utf-8");

  await Promise.all([
    db.set("asset:widget.js", widgetJs),
    db.set("asset:floating.js", floatingJs),
    db.set("asset:cap_wasm_bg.wasm", Buffer.from(wasmBinary)),
    db.set("asset:cap_wasm.js", wasmJs),
    db.set(
      "asset:cache-config",
      JSON.stringify({
        lastUpdate: Date.now() + 365 * 24 * 60 * 60 * 1000, // 1 year in the future
        versions: { widget: versions.widget, wasm: versions.wasm },
      }),
    ),
  ]);

  console.log(
    `[load-assets] Loaded widget@${versions.widget}, wasm@${versions.wasm} into Redis`,
  );

  await db.quit();
}

loadAssets().catch((err) => {
  console.error("[load-assets] Failed:", err.message);
  process.exit(1);
});
