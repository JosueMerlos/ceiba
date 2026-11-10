# E2E image: Playwright with the browsers included. The image version MUST match @playwright/test in
# frontend/e2e/package.json (checked by infra/scripts/check-versions.sh). Node 26.13.0 ships in the image.
FROM mcr.microsoft.com/playwright:v1.65.0-noble

ARG HOST_UID=1000
ARG HOST_GID=1000
ARG PNPM_VERSION=12.18.0

RUN npm install --global "pnpm@${PNPM_VERSION}" \
 && npm cache clean --force

# Non-root user with the host's UID/GID (as in frontend.Dockerfile): the node_modules volumes are shared with the panel
# containers and must not end up root-owned.
RUN groupadd --gid "${HOST_GID}" --non-unique app \
 && useradd --uid "${HOST_UID}" --gid "${HOST_GID}" --non-unique --create-home --shell /bin/bash app \
 && mkdir -p /app/frontend/node_modules /app/frontend/e2e/node_modules \
 && chown -R "${HOST_UID}:${HOST_GID}" /app

ENV npm_config_store_dir=/app/frontend/node_modules/.pnpm-store \
    CI=true

USER app
WORKDIR /app/frontend/e2e
