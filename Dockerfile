# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?name=ubuntu
# https://hub.docker.com/_/ubuntu/tags
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian/tags?name=trixie-20260202-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: docker.io/hexpm/elixir:1.19.5-erlang-28.3.1-debian-trixie-20260202-slim
#
ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.3.1
ARG DEBIAN_VERSION=trixie-20260202-slim

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="docker.io/debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# Git SHA from deploy.yml --build-arg; must match runtime SENTRY_RELEASE.
# ARG must be declared inside the stage (pre-FROM ARGs are not in scope here).
ARG SENTRY_RELEASE=""
ENV SENTRY_RELEASE=${SENTRY_RELEASE}

# install build dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git nodejs npm \
  && rm -rf /var/lib/apt/lists/*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force \
  && mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

RUN mix assets.setup

COPY priv priv

COPY lib lib

# Compile the release
RUN mix compile

COPY assets assets

RUN npm ci --prefix assets

# compile assets
RUN mix assets.deploy

# Upload frontend source maps from the same build that ships, then strip .map files
# so they are not served publicly. Skipped when SENTRY_AUTH_TOKEN is absent (e.g.
# local docker build, GHCR multi-arch job).
RUN --mount=type=secret,id=SENTRY_AUTH_TOKEN \
  set -eu; \
  if [ -f /run/secrets/SENTRY_AUTH_TOKEN ] && [ -n "${SENTRY_RELEASE}" ]; then \
    export SENTRY_AUTH_TOKEN="$(cat /run/secrets/SENTRY_AUTH_TOKEN)"; \
    echo "Uploading source maps for release ${SENTRY_RELEASE}..."; \
    npx --yes @sentry/cli@2 sourcemaps upload \
      --org crit-md \
      --project crit-web-frontend \
      --release "${SENTRY_RELEASE}" \
      --url-prefix '~/assets/js' \
      priv/static/assets/js; \
  else \
    echo "Skipping source map upload (secret=$([ -f /run/secrets/SENTRY_AUTH_TOKEN ] && echo present || echo absent), release=${SENTRY_RELEASE:-empty})"; \
  fi; \
  find priv/static/assets/js -name '*.map' -delete

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS final

RUN apt-get update \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses6 locales ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
  && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/crit ./

USER root
RUN chmod +x /app/bin/docker-entrypoint
USER nobody

CMD ["/app/bin/docker-entrypoint"]
