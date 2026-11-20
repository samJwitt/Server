# Builds a self-contained Lost City server image: every source is cloned and built here, at image
# build time, so the host only needs this image plus a directory for save data.
#
# Bump a pin to move a subproject forward. Patches in patches/<project>/ are applied on top with `git am`.

ARG NODE_IMAGE=node:26-slim
ARG BUN_IMAGE=oven/bun:1

# ---- sources ----
FROM alpine/git:latest AS src

ARG REPO_ORG=https://github.com/LostCityRS
# rev 274
ARG ENGINE_REF=1d25566cb53e7af1b1cb18ade8af996316c19614
ARG CONTENT_REF=2b62ae68dfed02b441bae47987a01d6bcbaeb358
ARG WEBCLIENT_REF=7d6ca61abda277cfed87d542e9e4aa3fe383b38d

COPY patches/ /patches/
COPY --chmod=755 docker/fetch.sh /usr/local/bin/fetch

WORKDIR /src
RUN fetch "$REPO_ORG/Engine-TS" "$ENGINE_REF" engine \
 && fetch "$REPO_ORG/Content" "$CONTENT_REF" content \
 && fetch "$REPO_ORG/Client-TS" "$WEBCLIENT_REF" webclient \
 && rm -rf engine/.git content/.git webclient/.git

# ---- web client ----
FROM ${BUN_IMAGE} AS web

WORKDIR /build
COPY --from=src /src/webclient/ ./
RUN bun install --frozen-lockfile && bun run build

# ---- base for the engine stages: prisma's schema engine needs openssl ----
FROM ${NODE_IMAGE} AS node-base

RUN apt-get update \
 && apt-get install -y --no-install-recommends openssl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# ---- engine: install deps and pack the cache ----
FROM node-base AS engine

WORKDIR /opt/lostcity
COPY --from=src /src/content/ content/
COPY --from=src /src/engine/ engine/
COPY --from=web /build/out/client.js engine/public/client/client.js
COPY config/world.json engine/data/config/world.json

WORKDIR /opt/lostcity/engine
# HUSKY=0 skips the git hooks install; dev dependencies stay because tsx and prisma are needed at runtime
RUN HUSKY=0 npm ci --no-audit --no-fund \
 && npm run build \
 && npm cache clean --force

# ---- runtime ----
FROM node-base

COPY --from=engine --chown=node:node /opt/lostcity/ /opt/lostcity/
COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/entrypoint

# save/ is the only state: db.sqlite and player saves are symlinked into it, as the old launcher did
WORKDIR /opt/lostcity/engine
RUN rm -rf data/players db.sqlite \
 && mkdir -p /opt/lostcity/save/players \
 && ln -s ../../save/players data/players \
 && ln -s ../save/db.sqlite db.sqlite \
 && chown -R node:node /opt/lostcity/save

USER node
VOLUME /opt/lostcity/save
EXPOSE 8888 43594 8898

ENTRYPOINT ["entrypoint"]
