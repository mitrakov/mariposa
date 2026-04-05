# docker build --file hue.dockerfile --tag mitrakov/hadoop-hue:1.0.0 . && say hola
FROM python:3.11-slim-bookworm AS builder

# Install build dependencies
RUN apt update && apt install -y \
    make gcc g++ wget git rsync curl ca-certificates gnupg \
    python3-dev libkrb5-dev libxml2-dev libxslt1-dev zlib1g-dev \
    libldap2-dev libsasl2-dev libssl-dev libffi-dev

# Install Node.js 18
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
    apt update && apt install -y nodejs

# Download HUE
ENV HUE_HOME=/opt/hue
RUN wget https://cdn.gethue.com/downloads/hue-4.11.0.tgz && \
    tar -xvf hue-4.11.0.tgz && mv hue-4.11.0 $HUE_HOME

WORKDIR $HUE_HOME

# Patch Makefile.vars to allow Python > 3.9
RUN sed -i 's/ifeq ($(shell test $(MINOR_VER) -lt 8; echo $$?),0)/ifeq (0,1)/g' Makefile.vars && \
    sed -i 's/$(error "$(VER_ERR_MSG)")/true/g' Makefile.vars

# Prepare Python 3.11 venv
RUN mkdir -p build/env
RUN python3.11 -m venv build/env

# Patch path bugs and remove broken packages
RUN find desktop/core -name "*.txt" -exec sed -i 's|\${ROOT}|/opt/hue|g' {} +
RUN sed -i '/slack-sdk==3.2.0/d' desktop/core/base_requirements.txt && \
    sed -i '/greenlet==/d' desktop/core/base_requirements.txt && \
    sed -i '/sasl==/d' desktop/core/base_requirements.txt && \
    sed -i '/PyYAML==5.4.1/d' desktop/core/base_requirements.txt && \
    sed -i '/numpy==1.23.1/d' desktop/core/requirements.txt && \
    sed -i '/pandas==1.4.2/d' desktop/core/requirements.txt

# Install broken Python dependencies
RUN ./build/env/bin/pip install --upgrade pip setuptools==67.8.0 wheel httplib2
RUN ./build/env/bin/pip install greenlet PyYAML pure-sasl thrift-sasl numpy pandas

# Install remaining requirements
RUN ./build/env/bin/pip install -r desktop/core/requirements.txt

# Main Build using Python 3.11 using legacy OpenSSL lib
RUN export NODE_OPTIONS=--openssl-legacy-provider && \
    make apps PYTHON_VER=python3.11 \
              SYS_PYTHON=/usr/local/bin/python3.11 \
              ENV_PYTHON=/opt/hue/build/env/bin/python3.11 \
              NPM_BIN=$(which npm)
