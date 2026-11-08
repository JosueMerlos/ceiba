# Imagen de DESARROLLO de la API (Rails) y del worker (Sidekiq). La de producción llega en M4.04.
FROM ruby:3.4.12-slim-trixie

ARG HOST_UID=1000
ARG HOST_GID=1000

RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends \
      build-essential curl git libpq-dev libyaml-dev pkg-config postgresql-client tzdata \
 && rm -rf /var/lib/apt/lists/*

# Usuario no root con el UID/GID del host. `-o` permite reutilizar un GID que ya existe
# en la imagen base (p. ej. GID 20 = staff en macOS, que en Debian es `dialout`).
RUN groupadd --gid "${HOST_GID}" --non-unique app \
 && useradd --uid "${HOST_UID}" --gid "${HOST_GID}" --non-unique --create-home --shell /bin/bash app \
 && mkdir -p /app/backend \
 && chown -R "${HOST_UID}:${HOST_GID}" /app /usr/local/bundle

COPY --chmod=0755 infra/docker/api-entrypoint.sh /usr/local/bin/api-entrypoint

ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_BIN=/usr/local/bundle/bin \
    PATH=/usr/local/bundle/bin:$PATH

USER app
WORKDIR /app/backend
ENTRYPOINT ["api-entrypoint"]
