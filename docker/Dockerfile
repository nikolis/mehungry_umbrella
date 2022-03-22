FROM bitwalker/alpine-elixir-phoenix:latest as builder
#ARG ALPINE_VERSION=3.8

#FROM elixir:1.7.2-alpine AS builder

WORKDIR /app

ENV MIX_ENV=prod \
    SECRET_KEY_BASE=$SECRET_KEY_BASE \
    AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
    AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
    DATABASE_URL=$DATABASE_URL \
    RDS_DB_NAME=$RDS_DB_NAME\
    RDS_HOSTNAME=$RDS_HOSTNAME\
    DB_HOST=$DB_HOST\
    DB_PORT=$DB_PORT\
    RDS_USERNAME=$RDS_USERNAME\
    RDS_PASSWORD=$RDS_PASSWORD\
    SHELL=/bin/bash

# install hex + rebar
RUN mix do local.hex --force, local.rebar --force 

COPY config config
COPY mix.* ./
COPY apps/mehungry/mix.exs ./apps/mehungry/
COPY apps/mehungry_api/mix.exs ./apps/mehungry_api/
COPY apps/mehungry_web/mix.exs ./apps/mehungry_web/
RUN apk add make

ENV PYTHONUNBUFFERED=1
RUN apk add --update --no-cache python3 && ln -sf python3 /usr/bin/python
RUN apk update && apk add --virtual build-dependencies build-base gcc wget git

RUN mix do deps.get --only $MIX_ENV, deps.compile, compile, phx.digest

COPY . /app/

# build assets
WORKDIR /app/apps/mehungry_web

RUN npm install --prefix ./assets/ ci --progress=false --no-audit --loglevel=error
RUN npm run deploy --prefix ./assets
RUN mix phx.digest

WORKDIR /app

RUN PORT=4000 MIX_ENV=prod mix do compile, release

# prepare release image
FROM bitwalker/alpine-elixir:1.10.3
RUN apk upgrade --no-cache && \ 
    apk add --no-cache postgresql-client bash openssl libgcc libstdc++ ncurses-libs

ARG VERSION=0.7.0

WORKDIR /app
COPY --from=builder /app/_build/prod/rel/mehungry_umbrella /app/

#RUN ln -s ./foilapp/lib/foilapi_web-${VERSION}/priv/static /app/static
ENV HOME=/app

EXPOSE 4000

ENTRYPOINT ["./bin/mehungry_umbrella", "start"]
