# docker build --file hue.dockerfile --tag mitrakov/hadoop-hue:1.0.0 .
# STAGE 1: The Builder (using Python 3.9)
FROM python:3.9-slim-bookworm AS builder

# Install build dependencies
RUN apt update && apt install -y make gcc g++ wget libkrb5-dev libxml2-dev libxslt1-dev zlib1g-dev
RUN apt install -y libldap2-dev libsasl2-dev libssl-dev libffi-dev

ENV HUE_HOME=/opt/hue
WORKDIR /opt

# Download and Unpack
RUN wget https://cdn.gethue.com/downloads/hue-4.11.0.tgz && \
    tar -xvf hue-4.11.0.tgz && \
    mv hue-4.11.0 $HUE_HOME

RUN apt install -y rsync

RUN apt install -y curl ca-certificates gnupg && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
    apt update && apt install nodejs -y

#FROM scratch
# COPY --from=builder /opt/hue /hue_compiled


# ... (builder setup: apt installs, etc) ...
RUN apt install -y git

WORKDIR $HUE_HOME
RUN export ROOT=$HUE_HOME
RUN mkdir -p build/env && touch build/env/stamp
RUN python3.9 -m venv build/env
RUN find desktop/core -name "*.txt" -exec sed -i 's|\${ROOT}|/opt/hue|g' {} +
RUN ./build/env/bin/pip install --upgrade pip setuptools==58.0.0 wheel
RUN apt install -y python3-dev libsasl2-dev libkrb5-dev
RUN sed -i '/slack-sdk==3.2.0/d' desktop/core/base_requirements.txt
RUN ./build/env/bin/pip install --no-build-isolation greenlet sasl

RUN sed -i '/greenlet==/d' desktop/core/base_requirements.txt && \
    sed -i '/sasl==/d' desktop/core/base_requirements.txt

RUN ./build/env/bin/pip install -r desktop/core/requirements.txt

RUN export NODE_OPTIONS=--openssl-legacy-provider && \
    make apps PYTHON_VER=python3.9 \
              SYS_PYTHON=/usr/local/bin/python3.9 \
              ENV_PYTHON=/opt/hue/build/env/bin/python3.9 \
              NPM_BIN=$(which npm)
