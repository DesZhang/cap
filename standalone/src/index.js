import { cors } from "@elysiajs/cors";
import { Elysia, file } from "elysia";
import { assetsServer } from "./assets.js";
import { auth } from "./auth.js";
import { capServer } from "./cap.js";
import { isDemoMode } from "./demo.js";
import { loadIPDB } from "./ipdb.js";
import { loadRswKeypair, startRswRefresh } from "./rsw-store.js";
import { server } from "./server.js";
import {
  checkCorsOrigin,
  loadCorsDefault,
  loadFiltering,
  loadHeaders,
  loadRatelimit,
} from "./settings-cache.js";
import { siteverifyServer } from "./siteverify.js";
import { publicStatic } from "./static.js";

const serverPort = process.env.SERVER_PORT || 3000;
const serverHostname = process.env.SERVER_HOSTNAME || "0.0.0.0";

new Elysia({
  prefix: process.env.BASE_PATH || "",
  serve: {
    port: serverPort,
    hostname: serverHostname,
  },
})
  .onBeforeHandle(({ set }) => {
    set.headers["X-Powered-By"] = "Cap Standalone";
  })
  .onError(({ error, code }) => {
    const serializeError = (err) =>
      err instanceof Error
        ? {
            name: err.name,
            message: err.message,
            stack: err.stack,
            ...(err.code ? { code: err.code } : {}),
            ...(err.cause ? { cause: String(err.cause) } : {}),
          }
        : err;

    if (["VALIDATION", "NOT_FOUND"].includes(code)) {
      return {
        success: false,
        error: error.code || code || "Request rejected",
        ...(process.env.SHOW_ERRORS === "true"
          ? { detail: serializeError(error) }
          : {}),
      };
    }

    const errorId = Bun.randomUUIDv7().split("-").pop();

    if (process.env.DISABLE_ERROR_LOGGING !== "true") {
      console.error(
        `[${error.code || "ERR"} ${errorId}]`,
        JSON.stringify({
          timestamp: new Date().toISOString(),
          error: serializeError(error),
          env: {
            bun: process.versions.bun,
            platform: process.platform,
            mem: process.memoryUsage(),
          },
        }),
      );
    }

    return {
      success: false,
      error: error.code || "Internal server error",
      detail:
        process.env.SHOW_ERRORS === "true"
          ? serializeError(error)
          : {
              troubleshooting:
                "http://trycap.dev/guide/standalone/options.html#error-messages",
              id: errorId,
            },
    };
  })
  .use(
    cors({
      origin: (request) => {
        const path = new URL(request.url).pathname;
        if (path === "/assets" || path.startsWith("/assets/")) return true;
        return checkCorsOrigin(request);
      },
      methods: ["GET", "POST"],
    }),
  )
  .use(publicStatic)
  .get("/", async ({ cookie, redirect, request }) => {
    const basePath = process.env.BASE_PATH || "";
    const pathname = new URL(request.url).pathname;
    if (basePath && basePath !== "/" && !pathname.endsWith("/")) {
      return redirect(`${basePath}/`);
    }
    if (isDemoMode()) return file("./public/index.html");
    return file(
      cookie.cap_authed?.value === "yes"
        ? "./public/index.html"
        : "./public/login.html",
    );
  })
  .use(auth)
  .use(server)
  .use(assetsServer)
  .use(capServer)
  .use(siteverifyServer)
  .listen(serverPort);

console.log(`🧢 Cap running on http://${serverHostname}:${serverPort}`);

await loadHeaders();
await loadRatelimit();
await loadCorsDefault();
await loadFiltering();
loadRswKeypair().catch((e) =>
  console.warn("[cap] RSW keypair load:", e.message),
);
startRswRefresh();
loadIPDB().catch((e) => console.warn("[cap] IP DB load:", e.message));
