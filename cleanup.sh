#!/usr/bin/env bash
#
# cleanup.sh - Detiene y elimina los contenedores del relay y del cliente,
#              y borra la red que los conectaba.
#
# Uso:  ./cleanup.sh
#
# Es idempotente: si no queda nada que borrar, termina sin error. Conviene
# ejecutarlo antes de cada ./deploy.sh, porque el despliegue falla si los
# contenedores ya existen.

# Sin 'set -e': queremos continuar aunque algun recurso ya no exista.
set -uo pipefail

NETWORK="nostr-net"
RELAY_NAME="nostr-relay"
CLIENT_NAME="coracle"

info() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
ok()   { printf '\033[1;32m  OK\033[0m %s\n' "$1"; }
skip() { printf '\033[1;33m  --\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }

docker info >/dev/null 2>&1 \
  || die "El daemon de Docker no responde. Abre Docker Desktop y reintenta."

# ---------------------------------------------------------------------------
# 1. Contenedores
# ---------------------------------------------------------------------------
info "Eliminando contenedores"

for c in "$RELAY_NAME" "$CLIENT_NAME"; do
  if docker container inspect "$c" >/dev/null 2>&1; then
    # -f detiene y elimina en un solo paso.
    docker rm -f "$c" >/dev/null 2>&1 && ok "Contenedor '${c}' eliminado" \
      || skip "No se pudo eliminar '${c}'"
  else
    skip "El contenedor '${c}' no existe"
  fi
done

# ---------------------------------------------------------------------------
# 2. Red
# ---------------------------------------------------------------------------
info "Eliminando la red '${NETWORK}'"

if docker network inspect "$NETWORK" >/dev/null 2>&1; then
  docker network rm "$NETWORK" >/dev/null 2>&1 && ok "Red '${NETWORK}' eliminada" \
    || skip "No se pudo eliminar la red (puede tener contenedores conectados)"
else
  skip "La red '${NETWORK}' no existe"
fi

# ---------------------------------------------------------------------------
# 3. Comprobacion
# ---------------------------------------------------------------------------
echo
info "Contenedores restantes de la practica"
found=$(docker ps -a --filter "name=${RELAY_NAME}" --filter "name=${CLIENT_NAME}" \
  --format '{{.Names}}\t{{.Status}}')
if [[ -z "$found" ]]; then
  ok "Ninguno"
else
  echo "$found"
fi

echo
info "Redes existentes"
docker network ls

echo
printf '\033[1;32mLimpieza completada.\033[0m\n'
