# docker build --file hue.dockerfile --tag mitrakov/hadoop-hue:1.0.0 .
FROM python:3.9-slim-bookworm AS builder

# install hundreds of tools (TODO: check)
RUN apt update && apt install -y make gcc g++ wget git rsync curl ca-certificates gnupg python3-dev libkrb5-dev libxml2-dev libxslt1-dev zlib1g-dev libldap2-dev libsasl2-dev libssl-dev libffi-dev libsasl2-dev libkrb5-dev
# install node.js (needed)
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
    apt update && apt install -y nodejs

# download HUE
ENV HUE_HOME=/opt/hue
RUN wget https://cdn.gethue.com/downloads/hue-4.11.0.tgz && tar -xvf hue-4.11.0.tgz && mv hue-4.11.0 $HUE_HOME

# prepare python venv
WORKDIR $HUE_HOME
RUN export ROOT=$HUE_HOME
RUN mkdir -p build/env && touch build/env/stamp
RUN python3.9 -m venv build/env

# patch bugs, remove slack
RUN find desktop/core -name "*.txt" -exec sed -i 's|\${ROOT}|/opt/hue|g' {} +
RUN sed -i '/slack-sdk==3.2.0/d' desktop/core/base_requirements.txt && \
    sed -i '/greenlet==/d' desktop/core/base_requirements.txt && \
    sed -i '/sasl==/d' desktop/core/base_requirements.txt

# install python dependencies
RUN ./build/env/bin/pip install --upgrade pip setuptools==58.0.0 wheel
RUN ./build/env/bin/pip install --no-build-isolation greenlet sasl
RUN ./build/env/bin/pip install -r desktop/core/requirements.txt

# main build
RUN export NODE_OPTIONS=--openssl-legacy-provider && \
    make apps PYTHON_VER=python3.9 \
              SYS_PYTHON=/usr/local/bin/python3.9 \
              ENV_PYTHON=/opt/hue/build/env/bin/python3.9 \
              NPM_BIN=$(which npm)
