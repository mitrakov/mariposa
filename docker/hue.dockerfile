# docker build --file hue.dockerfile --tag mitrakov/hadoop-hue:1.0.0 .
FROM ubuntu:26.04 AS builder

# install tools
RUN apt update && apt install --yes software-properties-common && add-apt-repository -y ppa:deadsnakes/ppa
RUN apt install --yes wget curl make git gcc g++ python3.9-dev python3.9-venv libkrb5-dev libsasl2-dev libldap2-dev

# download HUE 4.11.0 (original: https://cdn.gethue.com/downloads/hue-4.11.0.tgz)
ENV HUE_HOME=/opt/hue
RUN wget --output-document=- http://mitrakoff.com/cache/hue-4.11.0.tgz | \
    tar --extract --gzip --directory /opt && mv /opt/hue-4.11.0 $HUE_HOME
WORKDIR $HUE_HOME

# download Node.js 18 (note it is for arm64!)
RUN curl -fsSL https://nodejs.org/dist/v18.19.0/node-v18.19.0-linux-arm64.tar.xz | tar -xJ --strip-components=1 -C /usr/local

# create virtual env
RUN mkdir -p build/env && python3.9 -m venv build/env

# fix invalid paths
RUN find desktop/core -name "*.txt" -exec sed -i 's|\${ROOT}|/opt/hue|g' {} +

# upgrade setuptools
RUN ./build/env/bin/pip install --upgrade pip setuptools==67.8.0 wheel

# manual patches + install psycopg2 to enable Postgres for HUE
RUN sed -i '/slack-sdk==3.2.0/d' desktop/core/base_requirements.txt
RUN sed -i '/greenlet==0.4.15/d' desktop/core/base_requirements.txt
RUN sed -i '/sasl==0.2.1/d'      desktop/core/base_requirements.txt
RUN build/env/bin/pip install "sasl>=0.3.1" "greenlet>=3.0.0" psycopg2-binary

# step 1: build HUE requirements
RUN build/env/bin/pip install -r desktop/core/requirements.txt

# step 2: build HUE
RUN export NODE_OPTIONS=--openssl-legacy-provider && make apps PYTHON_VER=python3.9

# fix invalid functions
RUN sed -i "s/_b64_decode_fn = getattr(base64, 'decodebytes', base64.decodestring)/_b64_decode_fn = base64.decodebytes/g" desktop/core/ext-py3/pysaml2-5.0.0/src/saml2/saml.py
RUN sed -i "s/_b64_encode_fn = getattr(base64, 'encodebytes', base64.encodestring)/_b64_encode_fn = base64.encodebytes/g" desktop/core/ext-py3/pysaml2-5.0.0/src/saml2/saml.py
