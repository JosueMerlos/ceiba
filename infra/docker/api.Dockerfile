# DEVELOPMENT image for the API (Rails) and the worker (Sidekiq).
FROM ruby:3.4.12-slim-trixie

ARG HOST_UID=1000
ARG HOST_GID=1000

# pg_dump/psql MUST match the server's major version (PostgreSQL 18): `db:structure:dump` fails with "server version
# mismatch" with an older client, and Debian trixie ships client 17. postgresql-client-18 comes from the official PGDG repo.
RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
 && install -d /usr/share/keyrings \
 && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/pgdg.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] https://apt.postgresql.org/pub/repos/apt trixie-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
 && apt-get update -qq \
 && apt-get install -y --no-install-recommends \
      build-essential git libpq-dev libyaml-dev pkg-config postgresql-client-18 tzdata \
 && rm -rf /var/lib/apt/lists/*

# Non-root user with the host's UID/GID. `--non-unique` allows reusing a GID that already exists in the base image
# (e.g. GID 20 = staff on macOS, which is `dialout` on Debian).
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
