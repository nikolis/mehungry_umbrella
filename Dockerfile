# ── Builder stage ────────────────────────────────────────────────────────────
FROM hexpm/elixir:1.16.2-erlang-26.2.5-alpine-3.19.0 AS builder

# Build-time tools only — not carried into the runtime image
RUN apk add --no-cache git build-base nodejs npm

WORKDIR /app

# Install Hex + Rebar (pinned via mix.lock, not downloaded at runtime)
RUN mix do local.hex --force, local.rebar --force

ENV MIX_ENV=prod

# ── Layer 1: dep manifests (cached until mix.lock changes) ───────────────────
COPY mix.* ./
COPY apps/mehungry/mix.* ./apps/mehungry/
COPY apps/mehungry_web/mix.* ./apps/mehungry_web/

RUN mix deps.get --only prod

# ── Layer 2: config (cached until config files change) ───────────────────────
COPY config ./config

RUN mix deps.compile

# ── Layer 3: JS deps (cached until package-lock.json changes) ────────────────
COPY apps/mehungry_web/assets/package.json \
     apps/mehungry_web/assets/package-lock.json \
     ./apps/mehungry_web/assets/

RUN npm ci --prefix apps/mehungry_web/assets

# ── Layer 4: application source (changes most often) ─────────────────────────
COPY apps ./apps
COPY rel ./rel

# Build and digest static assets
RUN mix tailwind.install --if-missing
RUN mix assets.deploy

# Compile app and build the OTP release
RUN mix release mehungry_umbrella

# ── Runtime stage ─────────────────────────────────────────────────────────────
# Minimal Alpine — no Elixir compiler, no Node, no build tools
FROM alpine:3.19 AS app

RUN apk add --no-cache \
    libstdc++ \
    openssl \
    ncurses-libs \
    postgresql-client \
    jq \
    bash

WORKDIR /app

# Copy only the compiled release from the builder
COPY --from=builder /app/_build/prod/rel/mehungry_umbrella ./
COPY --from=builder /app/entrypoint.sh ./entrypoint.sh

RUN chmod +x ./entrypoint.sh

# Phoenix HTTP
EXPOSE 4000
# Erlang EPMD
EXPOSE 4369
# Intra-node communication
EXPOSE 9000-9010
# :erpc
EXPOSE 9090

CMD ["sh", "./entrypoint.sh"]
