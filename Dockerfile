FROM bitwalker/alpine-elixir-phoenix:latest as builder

# install build dependencies
RUN apk add --update git build-base nodejs npm yarn

RUN mkdir mehungry_umbrella
WORKDIR /mehungry_umbrella

# install Hex + Rebar
RUN mix do local.hex --force, local.rebar --force

# set build ENV
ENV MIX_ENV=prod

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


RUN mix deps.get --only ${MIX_ENV}
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
FROM bitwalker/alpine-elixir-phoenix:latest as  app_container
# install runtime dependencies
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
ENV DATABASE_URL: ${DATABASE_URL}

# copy release to app container
COPY --from=builder /mehungry_umbrella/_build/prod/rel/mehungry_umbrella/ .
RUN apk add --update openssl postgresql-client

EXPOSE 4000

CMD ["sh", "bin/mehungry_umbrella", "start"]
