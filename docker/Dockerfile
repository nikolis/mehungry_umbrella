FROM bitwalker/alpine-elixir-phoenix:latest as builder
#ARG ALPINE_VERSION=3.8
#FROM elixir:1.7.2-alpine AS builder
#WORKDIR /app

#ENV MIX_ENV=$MIX_ENV \
 #   AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  #  AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
   # DATABASE_URL=$DATABASE_URL \
    #SHELL=/bin/bash

#RUN echo $AWS_ACCESS_KEY_ID
#RUN echo $MIX_ENV
ARG MIX_ENV=${MIX_ENV}
ENV MIX_ENV=${MIX_ENV}

# install hex + rebar
RUN apk add --update git build-base nodejs npm yarn

RUN mkdir mehungry_umbrella
WORKDIR /mehungry_umbrella

# install Hex + Rebar
RUN mix do local.hex --force, local.rebar --force

# set build ENV
ENV MIX_ENV=prod
RUN echo $MIX_ENV

# Install dependencies
RUN mkdir ./apps
RUN mkdir ./apps/mehungry
RUN mkdir ./apps/mehungry_web
RUN mkdir ./apps/mehungry_web/assets/

# Install JS dependencies
COPY ./apps/mehungry_web/assets/package.json ./apps/mehungry_web/assets/
COPY ./apps/mehungry_web/assets/  ./apps/mehungry_web/assets/

RUN npm i --prefix ./apps/mehungry_web/assets/
# Install mix dependecies
COPY mix.* ./
COPY ./apps/mehungry/mix.* ./apps/mehungry
COPY ./apps/mehungry_web/mix.* ./apps/mehungry_web


COPY config ./config

RUN mix deps.get --only $MIX_ENV
RUN mix assets.build 
RUN mix deps.compile

# Build front-end
COPY ./apps/mehungry_web/assets ./apps/mehungry_web/assets
RUN mix assets.deploy --prefix ./apps/mehungry_web/assets

# Copy app code
COPY apps ./apps

#RUN mix phx.digest

# build release
RUN PORT=4000 mix release mehungry_umbrella

# prepare release image
FROM bitwalker/alpine-elixir-phoenix:latest as  app
ARG MIX_ENV=${MIX_ENV}
ENV MIX_ENV=${MIX_ENV}

ENV AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
    AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
    DATABASE_URL=$DATABASE_URL \
    SHELL=/bin/bash
    
# install runtime dependencies
RUN apk add --update openssl postgresql-client
#RUN echo $AWS_ACCESS_KEY_ID
RUN echo $MIX_ENV

EXPOSE 4000
# copy release to app container
COPY --from=builder /mehungry_umbrella/_build/prod/rel/mehungry_umbrella/ .

CMD ["sh", "bin/mehungry_umbrella", "start"]

