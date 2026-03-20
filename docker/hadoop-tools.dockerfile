# docker build --file hadoop-tools.dockerfile --tag mitrakov/hadoop-tools:1.0.0 .
FROM mitrakov/hadoop-base:1.0.0
LABEL author="Artem Mitrakov (mitrakov-artem@yandex.ru)"


# sudo:        to start services
# ssh:         for Hadoop
# postgresql:  for Hive Metastore (pin version: postgresql-16)
# python3-pip: for Airflow
# iproute, mc: optional
RUN apt update && apt install -y sudo openssh-server postgresql-16 python3-pip iproute2 mc && apt clean
