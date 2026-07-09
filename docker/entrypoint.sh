#!/bin/bash
# Entrypoint compartido para worldserver/bnetserver dentro del contenedor runtime.
# Uso: entrypoint.sh worldserver|bnetserver [args...]
set -euo pipefail

SERVICE="${1:?Uso: entrypoint.sh worldserver|bnetserver}"
shift || true

ETC="/opt/bfacore/etc"
CONF="${ETC}/${SERVICE}.conf"
DIST="${ETC}/${SERVICE}.conf.dist"

DB_HOST="${DB_HOST:-mysql}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-root}"
DB_PASS="${DB_PASS:-admin}"

if [ ! -f "$CONF" ]; then
  echo "[entrypoint] Generando ${CONF} a partir de ${DIST}"
  cp "$DIST" "$CONF"
  sed -i \
    -e "s#127.0.0.1;3306;root;admin;bfa_auth#${DB_HOST};${DB_PORT};${DB_USER};${DB_PASS};bfa_auth#g" \
    -e "s#127.0.0.1;3306;root;admin;bfa_world#${DB_HOST};${DB_PORT};${DB_USER};${DB_PASS};bfa_world#g" \
    -e "s#127.0.0.1;3306;root;admin;bfa_characters#${DB_HOST};${DB_PORT};${DB_USER};${DB_PASS};bfa_characters#g" \
    -e "s#127.0.0.1;3306;root;admin;bfa_hotfixes#${DB_HOST};${DB_PORT};${DB_USER};${DB_PASS};bfa_hotfixes#g" \
    "$CONF"

  # El auto-updater de DBUpdater (DBUpdater.cpp) necesita el binario `mysql`
  # (no instalado en la imagen runtime) y el arbol fuente sql/ tal como
  # estaba en /src durante la build (no existe en runtime). Como el esquema
  # ya se importa a mano con `docker compose run --rm db-import`, lo
  # desactivamos para evitar que worldserver salga con exit 1 sin loguear
  # nada util al respecto.
  sed -i -e "s#^Updates\.EnableDatabases.*#Updates.EnableDatabases = 0#" "$CONF"

  # Los .conf.dist traen paths con separador de Windows (ej. ".\ClientData",
  # ".\Data\Logs"), que en Linux son un nombre de archivo literal en vez de
  # una ruta relativa. Convertimos los backslashes a "/" solo en las lineas
  # de paths conocidas.
  sed -i -E '/^(DataDir|LogsDir)[[:space:]]*=/ s#\\#/#g' "$CONF"
fi

echo "[entrypoint] Esperando a MySQL en ${DB_HOST}:${DB_PORT}..."
for i in $(seq 1 60); do
  if (exec 3<>"/dev/tcp/${DB_HOST}/${DB_PORT}") 2>/dev/null; then
    exec 3<&- 3>&-
    break
  fi
  sleep 2
done

mkdir -p /opt/bfacore/bin/Logs /opt/bfacore/bin/Data/Logs

cd /opt/bfacore/bin
exec "./${SERVICE}" "$@"
