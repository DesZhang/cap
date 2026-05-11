import Redis from "ioredis";

const redisUrl =
  process.env.REDIS_URL || process.env.VALKEY_URL || "redis://localhost:6379";

const clusterUrls = process.env.REDIS_CLUSTER_URLS;

const keyPrefix = process.env.REDIS_KEY_PREFIX || "cap:";

const commonOptions = {
  enableAutoPipelining: true,
  lazyConnect: false,
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

db.on("ready", () => {
  console.log("[db] Redis connection ready");
});
db.on("error", (err) => {
  console.error("[db] Redis error:", err.message);
});

await db.ping();

/**
 * Attach a send() method to the db instance so that calling code using
 * db.send("SET", [...]) continues to work without changes.
 * Bun: db.send("SET", [key, val, ...args])
 * ioredis: db.send_command("SET", [key, val, ...args])
 */
db.send = (command, args) => db.send_command(command, args);

export async function hgetall(key) {
  const data = await db.hgetall(key);
  if (!data) return {};
  if (typeof data === "object" && !Array.isArray(data)) return data;
  const obj = {};
  for (let i = 0; i < data.length; i += 2) {
    obj[data[i]] = data[i + 1];
  }
  return obj;
}

export { db };
