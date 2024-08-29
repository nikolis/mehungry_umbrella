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

RUN mix deps.get --only "prod"
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

# copy release to app container
COPY --from=builder /mehungry_umbrella/_build/prod/rel/mehungry_umbrella/ .
RUN apk add --update openssl postgresql-client
ENV MIX_ENV="prod"
EXPOSE 4000

CMD ["sh", "bin/mehungry_umbrella", "start"]
