# docker build --file hue.dockerfile --tag mitrakov/hadoop-hue:1.0.0 .; say hola
FROM ubuntu:26.04 AS builder

# install wget
RUN apt update && apt install --yes wget

# download HUE from my server (original with VPN: https://cdn.gethue.com/downloads/hue-4.11.0.tgz)
ENV HUE_HOME=/opt/hue
RUN wget http://mitrakoff.com/cache/hue-4.11.0.tgz && tar -xvf hue-4.11.0.tgz && mv hue-4.11.0 $HUE_HOME

# install build dependencies
RUN apt install --yes software-properties-common && add-apt-repository -y ppa:deadsnakes/ppa
RUN apt install --yes \
    make gcc g++ git rsync ca-certificates gnupg pkg-config curl \
    python3.11 python3.11-dev python3.11-venv \
    libkrb5-dev libxml2-dev libxslt1-dev zlib1g-dev \
    libldap2-dev libsasl2-dev libssl-dev libffi-dev 

WORKDIR $HUE_HOME

# patch Makefile.vars to allow Python > 3.9
RUN sed -i 's/ifeq ($(shell test $(MINOR_VER) -lt 8; echo $$?),0)/ifeq (0,1)/g' Makefile.vars && \
    sed -i 's/$(error "$(VER_ERR_MSG)")/true/g' Makefile.vars

# prepare Python 3.11 venv
RUN mkdir -p build/env && python3.11 -m venv build/env

# patch path bugs and remove broken packages
RUN find desktop/core -name "*.txt" -exec sed -i 's|\${ROOT}|/opt/hue|g' {} +
RUN sed -i '/slack-sdk==3.2.0/d' desktop/core/base_requirements.txt && \
    sed -i '/greenlet==/d' desktop/core/base_requirements.txt && \
    sed -i '/sasl==/d' desktop/core/base_requirements.txt && \
    sed -i '/lxml==/d' desktop/core/requirements.txt && \
    sed -i '/PyYAML==5.4.1/d' desktop/core/base_requirements.txt && \
    sed -i '/numpy==1.23.1/d' desktop/core/requirements.txt && \
    sed -i '/pandas==1.4.2/d' desktop/core/requirements.txt


# install broken Python dependencies
RUN ./build/env/bin/pip install --upgrade pip setuptools==67.8.0 wheel httplib2
RUN ./build/env/bin/pip install greenlet PyYAML pure-sasl thrift-sasl numpy pandas gssapi
RUN CFLAGS="-I/usr/include/libxml2" ./build/env/bin/pip install lxml==5.1.0

# install remaining requirements
RUN ./build/env/bin/pip install -r desktop/core/requirements.txt

# install Node.js 18 (note that it is for ARM64!)
RUN curl -fsSL https://nodejs.org/dist/v18.19.0/node-v18.19.0-linux-arm64.tar.xz | tar -xJ --strip-components=1 -C /usr/local

# main build using legacy OpenSSL lib
RUN export NODE_OPTIONS=--openssl-legacy-provider && \
    make apps PYTHON_VER=python3.11 \
              SYS_PYTHON=/usr/bin/python3.11 \
              ENV_PYTHON=$HUE_HOME/build/env/bin/python3.11 \
              NPM_BIN=/usr/bin/npm

# post-action: fix Python issues
RUN sed -i "s/_b64_decode_fn = getattr(base64, 'decodebytes', base64.decodestring)/_b64_decode_fn = base64.decodebytes/g" desktop/core/ext-py3/pysaml2-5.0.0/src/saml2/saml.py
RUN sed -i "s/_b64_encode_fn = getattr(base64, 'encodebytes', base64.encodestring)/_b64_encode_fn = base64.encodebytes/g" desktop/core/ext-py3/pysaml2-5.0.0/src/saml2/saml.py
RUN sed -i "s/self.cbt_struct = kerberos.channelBindings/self.cbt_struct = None # /g" build/env/lib/python3.11/site-packages/requests_kerberos/kerberos_.py
