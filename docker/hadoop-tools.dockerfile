# docker build --file hadoop-tools.dockerfile --tag mitrakov/hadoop-tools:1.0.0 .
FROM mitrakov/hadoop-base:1.0.0
LABEL author="Artem Mitrakov (mitrakov-artem@yandex.ru)"

# ssh is required for Hadoop, sudo is required to start services, postgresql for Hive Metastore, iproute for ip (opt), mc is opt
# pin version: postgresql-16
RUN apt update && apt install -y openssh-server postgresql-16 sudo iproute2 mc
