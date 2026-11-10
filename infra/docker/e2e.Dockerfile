# Imagen de los E2E (M0.12): Playwright con los navegadores incluidos. La versión de la imagen DEBE ser la de
# @playwright/test en frontend/e2e/package.json (infra/scripts/check-versions.sh lo verifica). Node 26.13.0 viene en la imagen.
FROM mcr.microsoft.com/playwright:v1.65.0-noble

ARG HOST_UID=1000
ARG HOST_GID=1000
ARG PNPM_VERSION=12.18.0

RUN npm install --global "pnpm@${PNPM_VERSION}" \
 && npm cache clean --force

# Usuario no root con el UID/GID del host (como frontend.Dockerfile): los volúmenes de node_modules se comparten con
# los contenedores del panel y no deben quedar con dueño root.
RUN groupadd --gid "${HOST_GID}" --non-unique app \
 && useradd --uid "${HOST_UID}" --gid "${HOST_GID}" --non-unique --create-home --shell /bin/bash app \
 && mkdir -p /app/frontend/node_modules /app/frontend/e2e/node_modules \
 && chown -R "${HOST_UID}:${HOST_GID}" /app

ENV npm_config_store_dir=/app/frontend/node_modules/.pnpm-store \
    CI=true

USER app
WORKDIR /app/frontend/e2e
