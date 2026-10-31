FROM postgres:17-bookworm
#Instalar pgbackrest y dependencias - crea y asigna permisos
RUN apt-get update \
    && apt-get install -y --no-install-recommends pgbackrest \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /var/lib/pgbackrest /var/log/pgbackrest \
    && chown -R postgres:postgres \
       /var/lib/pgbackrest /var/log/pgbackrest

CMD ["postgres"]
