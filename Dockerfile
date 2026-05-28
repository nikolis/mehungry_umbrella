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
ENV DATABASE_URL ${DATABASE_URL}

# Install dependencies
RUN mkdir ./apps
RUN mkdir ./apps/mehungry
RUN mkdir ./apps/mehungry_web
RUN mkdir ./apps/mehungry_web/assets/

# Install JS dependencies
#COPY ./apps/mehungry_web/assets/package.json ./apps/mehungry_web/assets/
#COPY ./apps/mehungry_web/assets/tailwind.config.js ./apps/mehungry_web/assets/


# Install mix dependecies
COPY mix.* ./
COPY ./apps/mehungry/mix.* ./apps/mehungry
COPY ./apps/mehungry_web/mix.* ./apps/mehungry_web

COPY config ./config
COPY ./pos_tagger.py ./pos_tagger.py
COPY ./entrypoint.sh ./entrypoint.sh

RUN mix deps.get --only ${MIX_ENV}
RUN MIX_ENV=prod mix compile


#RUN mix assets.build  
#RUN mix deps.compile

# Build front-end
COPY ./apps/mehungry_web/assets ./apps/mehungry_web/assets
COPY ./apps/mehungry/lib ./apps/mehungry/lib
COPY ./apps/mehungry_web/lib ./apps/mehungry_web/lib
COPY ./apps/mehungry_web/priv/static ./apps/mehungry_web/priv/static/

RUN npm i --prefix ./apps/mehungry_web/assets/

RUN mix tailwind.install  --if-missing
RUN MIX_ENV=prod mix assets.deploy

# Copy app code
COPY apps ./apps
COPY rel rel

#RUN mix phx.digest

# build release
RUN PORT=4000 MIX_ENV=prod  mix release mehungry_umbrella

# prepare release image
FROM bitwalker/alpine-elixir-phoenix:latest as  app_container
# install runtime dependencies

# copy release to app container
COPY --from=builder /mehungry_umbrella/_build/prod/rel/mehungry_umbrella/ .
COPY --from=builder /mehungry_umbrella/pos_tagger.py ./pos_tagger.py
copy --from=builder /mehungry_umbrella/entrypoint.sh ./entrypoint.sh 

RUN apk add --update openssl postgresql-client jq 
# Install build dependencies for spaCy
RUN apk add --no-cache \
    build-base \
    libffi-dev \
    openssl-dev \
    musl-dev \
    gcc \
    g++ \
    python3-dev \
    py3-pip

# Default Phoenix server port
EXPOSE 4000

# Erlang EPMD port
EXPOSE 4369

# Intra-Erlang communication ports
EXPOSE 9000-9010

# :erpc default port
EXPOSE 9090


# Create a virtual environment
ENV VENV_PATH=/opt/venv
RUN python -m venv $VENV_PATH

# Activate the virtual environment by modifying PATH
ENV PATH="$VENV_PATH/bin:$PATH"

# Install spaCy inside the virtual environment
# --prefer-binary picks up the musllinux wheels (Alpine-compatible)
RUN pip install --upgrade pip \
 && pip install --no-cache-dir --prefer-binary 'spacy==3.7.4' \
 && python -m spacy download en_core_web_sm

 
CMD ["sh", "./entrypoint.sh"]
