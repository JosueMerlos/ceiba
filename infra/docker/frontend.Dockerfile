# Imagen de DESARROLLO del frontend (Vite dev server para panel y booking).
FROM node:26.13.0-trixie-slim

ARG HOST_UID=1000
ARG HOST_GID=1000
ARG PNPM_VERSION=12.18.0

RUN npm install --global "pnpm@${PNPM_VERSION}" \
 && npm cache clean --force

# Usuario no root con el UID/GID del host. `--non-unique` permite reutilizar un GID ya
# existente en la imagen (p. ej. GID 20 = staff en macOS, `dialout` en Debian) y evita
# el choque con el usuario `node` (1000) de la imagen base.
RUN groupadd --gid "${HOST_GID}" --non-unique app \
 && useradd --uid "${HOST_UID}" --gid "${HOST_GID}" --non-unique --create-home --shell /bin/bash app \
 && mkdir -p /app/frontend/node_modules /app/frontend/apps/panel/node_modules /app/frontend/apps/booking/node_modules /app/frontend/packages/config/node_modules \
 && chown -R "${HOST_UID}:${HOST_GID}" /app

COPY --chmod=0755 infra/docker/frontend-entrypoint.sh /usr/local/bin/frontend-entrypoint

# El store de pnpm vive en el mismo volumen que node_modules para que use hard links.
ENV npm_config_store_dir=/app/frontend/node_modules/.pnpm-store \
    CI=true

USER app
WORKDIR /app/frontend
ENTRYPOINT ["frontend-entrypoint"]
