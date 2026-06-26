# Install confluent_kafka
If you see an error:
```
ModuleNotFoundError: No module named 'confluent_kafka'
```


## Simple (PLAINTEXT Kafka)
```sh
sudo apt install pip
pip install confluent_kafka --break-system-packages
```


## SASL with Kerberos (GSS_API)
By default, `confluent_kafka` doesn't support SASL:
```
cimpl.KafkaException: KafkaError{code=_INVALID_ARG,val=-186,str="Failed to create producer: No provider for SASL mechanism GSSAPI: recompile librdkafka with libsasl2 or openssl support. Current build options: PLAIN SASL_SCRAM OAUTHBEARER"}
```

Install `confluent_kafka` from the wheel:
```sh
sudo apt install pip
sudo tar --directory=/ -xzvf librdkafka-2.15.0-bin-linux_x86_64.tar.gz                     # extract the pre-compiled C libraries directly into system paths
sudo ldconfig                                                                              # refresh the operating system linker cache
pip install confluent_kafka-2.14.2-cp314-cp314-linux_x86_64.whl --break-system-packages    # install wheel directly with pip instantly
```


## Build from sources
This is a guide how to build `confluent-kafka` and `librdkafka` from sources.
```sh
sudo apt install git gcc g++ make python3-dev
git clone https://github.com/confluentinc/librdkafka.git
cd librdkafka/
./configure --enable-sasl
make
sudo make install    # install the binaries and header files to system directories (/usr/local/)
sudo ldconfig        # update system linker cache

pip install --no-binary :all: confluent-kafka --break-system-packages
```

Out:
```
Collecting confluent-kafka
  Using cached confluent_kafka-2.14.2.tar.gz (289 kB)
  Installing build dependencies ... done
  Getting requirements to build wheel ... done
  Preparing metadata (pyproject.toml) ... done
Building wheels for collected packages: confluent-kafka
  Building wheel for confluent-kafka (pyproject.toml) ... done
  Created wheel for confluent-kafka: filename=confluent_kafka-2.14.2-cp314-cp314-linux_x86_64.whl size=576041 sha256=f04fc698274ef81f8ec11f6ea41cc3faa530c835264c7515eadc217384197e5b
  Stored in directory: /home/hadoop/.cache/pip/wheels/99/59/3b/c6c0d81a35dbef79daa2637c938c74c7d2d256970831d3f722
Successfully built confluent-kafka
Installing collected packages: confluent-kafka
Successfully installed confluent-kafka-2.14.2
```


Create a distr:
```sh
cp -v /home/hadoop/.cache/pip/wheels/99/59/3b/c6c0d81a35dbef79daa2637c938c74c7d2d256970831d3f722/confluent_kafka-2.14.2-cp314-cp314-linux_x86_64.whl /home/hadoop/confluent_kafka-2.14.2-cp314-cp314-linux_x86_64.whl
tar -czvf librdkafka-built.tar.gz /usr/local/lib/librdkafka* /usr/local/include/librdkafka
```
