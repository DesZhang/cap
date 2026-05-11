FROM oven/bun:slim AS base
WORKDIR /usr/src/app

FROM base AS install
RUN mkdir -p /temp/dev/standalone /temp/dev/core
COPY standalone/package.json standalone/bun.lock /temp/dev/standalone/
COPY core/package.json /temp/dev/core/
COPY core/src /temp/dev/core/src
RUN cd /temp/dev/standalone && bun install

FROM base AS prod
RUN mkdir -p /temp/prod/standalone /temp/prod/core
COPY standalone/package.json standalone/bun.lock /temp/prod/standalone/
COPY core/package.json /temp/prod/core/
COPY core/src /temp/prod/core/src
RUN cd /temp/prod/standalone && bun install --production

FROM base AS prerelease
COPY --from=install /temp/dev/standalone/node_modules node_modules
COPY standalone/. .

# ── Fetch widget + WASM assets from CDN at build time ──────
ARG CAP_WIDGET_VERSION=0.1.50
ARG CAP_WASM_VERSION=0.0.7

FROM alpine:3.20 AS asset-fetcher
ARG CAP_WIDGET_VERSION
ARG CAP_WASM_VERSION
RUN mkdir -p /assets && \
    apk add --no-cache curl && \
    curl -fsSL -o /assets/widget.js \
      "https://cdn.jsdelivr.net/npm/@cap.js/widget@${CAP_WIDGET_VERSION}" && \
    curl -fsSL -o /assets/floating.js \
      "https://cdn.jsdelivr.net/npm/@cap.js/widget@${CAP_WIDGET_VERSION}/cap-floating.min.js" && \
    curl -fsSL -o /assets/cap_wasm_bg.wasm \
      "https://cdn.jsdelivr.net/npm/@cap.js/wasm@${CAP_WASM_VERSION}/browser/cap_wasm_bg.wasm" && \
    curl -fsSL -o /assets/cap_wasm.js \
      "https://cdn.jsdelivr.net/npm/@cap.js/wasm@${CAP_WASM_VERSION}/browser/cap_wasm.min.js" && \
    echo "{\"widget\":\"${CAP_WIDGET_VERSION}\",\"wasm\":\"${CAP_WASM_VERSION}\"}" \
      > /assets/versions.json

FROM base AS release
COPY --from=prod /temp/prod/standalone/node_modules node_modules
COPY --from=prerelease /usr/src/app .
COPY --from=asset-fetcher /assets /usr/src/app/baked-assets
WORKDIR /usr/src/app
RUN mkdir -p data && chown bun:bun data

EXPOSE 3000/tcp

USER bun

ENTRYPOINT [ "/usr/src/app/scripts/entrypoint.sh" ]
