# DEVELOPMENT image for the frontend (Vite dev server for panel and booking).
FROM node:26.13.0-trixie-slim

ARG HOST_UID=1000
ARG HOST_GID=1000
ARG PNPM_VERSION=12.18.0

RUN npm install --global "pnpm@${PNPM_VERSION}" \
 && npm cache clean --force

# Non-root user with the host's UID/GID. `--non-unique` allows reusing a GID that already exists in the image (e.g.
# GID 20 = staff on macOS, `dialout` on Debian) and avoids clashing with the base image's `node` user (1000).
RUN groupadd --gid "${HOST_GID}" --non-unique app \
 && useradd --uid "${HOST_UID}" --gid "${HOST_GID}" --non-unique --create-home --shell /bin/bash app \
 && mkdir -p /app/frontend/node_modules /app/frontend/apps/panel/node_modules /app/frontend/apps/booking/node_modules /app/frontend/packages/config/node_modules /app/frontend/packages/api-client/node_modules /app/frontend/packages/ui/node_modules /app/frontend/packages/i18n/node_modules /app/frontend/e2e/node_modules /app/backend/openapi \
 && chown -R "${HOST_UID}:${HOST_GID}" /app

COPY --chmod=0755 infra/docker/frontend-entrypoint.sh /usr/local/bin/frontend-entrypoint

# The pnpm store lives on the same volume as node_modules so it can use hard links.
ENV npm_config_store_dir=/app/frontend/node_modules/.pnpm-store \
    CI=true

USER app
WORKDIR /app/frontend
ENTRYPOINT ["frontend-entrypoint"]
