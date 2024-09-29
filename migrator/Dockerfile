FROM bitwalker/alpine-elixir-phoenix:latest as builder


# install build dependencies
RUN apk add --update git build-base nodejs npm yarn

RUN mkdir mehungry_umbrella
WORKDIR /mehungry_umbrella

# install Hex + Rebar
RUN mix do local.hex --force, local.rebar --force

# set build ARG
ARG DATABASE_URL

# set build ENV
ENV MIX_ENV=prod
ENV DATABASE_URL ${DATABASE_URL}

ARG MIX_ENV
ARG AWS_ASSETS_BUCKET_NAME
ARG AWS_ACCESS_KEY_ID
ARG AWS_SECRET_ACCESS_KEY
ARG FACEBOOK_CLIENT_ID
ARG FACEBOOK_CLIENT_SECRET
ARG GOOGLE_CLIENT_ID
ARG GOOGLE_CLIENT_SECRET
ARG SECRET_KEY_BASE 
ARG DATABASE_URL

ENV MIX_ENV  ${MIX_ENV}
ENV AWS_ASSETS_BUCKET_NAME  ${AWS_ASSETS_BUCKET_NAME}
ENV AWS_ACCESS_KEY_ID  ${AWS_ACCESS_KEY_ID}
ENV AWS_SECRET_ACCESS_KEY  ${AWS_SECRET_ACCESS_KEY}
ENV FACEBOOK_CLIENT_ID  ${FACEBOOK_CLIENT_ID}
ENV FACEBOOK_CLIENT_SECRET  ${FACEBOOK_CLIENT_SECRET}
ENV GOOGLE_CLIENT_ID  ${GOOGLE_CLIENT_ID}
ENV GOOGLE_CLIENT_SECRET  ${GOOGLE_CLIENT_SECRET}
ENV SECRET_KEY_BASE ${SECRET_KEY_BASE}
ENV SECRET_KEY_BASE ${SECRET_KEY_BASE}
ENV DATABASE_URL ${DATABASE_URL}

# Install dependencies
RUN mkdir ./apps
RUN mkdir ./apps/mehungry

# Install mix dependecies
COPY mix.* ./
COPY ./apps/mehungry/mix.* ./apps/mehungry

COPY ./apps/mehungry/lib ./apps/mehungry/lib
# Copy app code
COPY apps ./apps

COPY config ./config

RUN mix deps.get --only ${MIX_ENV}
#RUN MIX_ENV=prod mix compile
#RUN mix assets.build  
#RUN mix deps.compile

# Build front-end
COPY ./apps/mehungry/priv/repo/migrations ./apps/mehungry/priv/repo/migrations

CMD ["mix", "ecto.migrate"]
