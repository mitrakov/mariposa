# docker build --file hue2.dockerfile --tag mitrakov/hadoop-hue2:1.0.0 .
FROM ubuntu:26.04 AS builder

# Install core build and download tools
RUN apt update && apt install --yes wget curl gnupg ca-certificates rsync git make gcc g++ pkg-config

# Add deadsnakes PPA to fetch Python 3.9 on modern Ubuntu
RUN apt install --yes software-properties-common && add-apt-repository -y ppa:deadsnakes/ppa

# Install Python 3.9 and the EXACT system-level libraries SASL, Kerberos, and LDAP need to compile
RUN apt update && apt install --yes \
    python3.9 python3.9-dev python3.9-venv \
    libkrb5-dev libxml2-dev libxslt1-dev zlib1g-dev \
    libldap2-dev libsasl2-dev libssl-dev libffi-dev \
    libsasl2-modules-gssapi-mit

# Download HUE 4.11.0
ENV HUE_HOME=/opt/hue
RUN wget http://mitrakoff.com/cache/hue-4.11.0.tgz && \
    tar -xvf hue-4.11.0.tgz && \
    mv hue-4.11.0 $HUE_HOME

WORKDIR $HUE_HOME

# Step 1: Fix hardcoded path bugs inside desktop requirements
RUN find desktop/core -name "*.txt" -exec sed -i 's|\${ROOT}|/opt/hue|g' {} +

# Step 2: Set up a clean Python 3.9 virtual environment
RUN mkdir -p build/env && python3.9 -m venv build/env

# Step 3: Upgrade core packaging tools inside the 3.9 venv
RUN ./build/env/bin/pip install --upgrade pip setuptools==67.8.0 wheel httplib2

# patches
RUN sed -i '/slack-sdk==3.2.0/d' desktop/core/base_requirements.txt
RUN sed -i '/sasl==0.2.1/d'      desktop/core/base_requirements.txt
RUN sed -i '/greenlet==0.4.15/d' desktop/core/base_requirements.txt
RUN ./build/env/bin/pip install "sasl>=0.3.1" "greenlet>=3.0.0"

# Step 4: Let's install the native requirements
RUN ./build/env/bin/pip install -r desktop/core/requirements.txt

# Install Node.js 18 (ARM64 specific) for building the frontend assets
RUN curl -fsSL https://nodejs.org/dist/v18.19.0/node-v18.19.0-linux-arm64.tar.xz | tar -xJ --strip-components=1 -C /usr/local

# Step 5: Compile the application using the legacy OpenSSL provider required by older Node builds
RUN export NODE_OPTIONS=--openssl-legacy-provider && \
    make apps PYTHON_VER=python3.9 \
              SYS_PYTHON=/usr/bin/python3.9 \
              ENV_PYTHON=$HUE_HOME/build/env/bin/python3.9 \
              NPM_BIN=/usr/bin/npm

RUN sed -i "s/_b64_decode_fn = getattr(base64, 'decodebytes', base64.decodestring)/_b64_decode_fn = base64.decodebytes/g" desktop/core/ext-py3/pysaml2-5.0.0/src/saml2/saml.py
RUN sed -i "s/_b64_encode_fn = getattr(base64, 'encodebytes', base64.encodestring)/_b64_encode_fn = base64.encodebytes/g" desktop/core/ext-py3/pysaml2-5.0.0/src/saml2/saml.py
