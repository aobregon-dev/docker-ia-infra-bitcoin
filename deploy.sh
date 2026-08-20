#!/usr/bin/env bash
#
# deploy.sh - Despliega un relay Nostr (nostr-rs-relay) y un cliente web
#             (Coracle), ambos conectados a una misma red Docker.
#
# Uso:  ./deploy.sh
#
# Si los contenedores ya existen el despliegue falla: ejecutar antes
# ./cleanup.sh para partir de cero.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuracion
# ---------------------------------------------------------------------------
NETWORK="nostr-net"

# Ambas imagenes solo publican variante linux/amd64. En Apple Silicon esto
# obliga a emulacion; declararlo evita el aviso y hace el script determinista.
PLATFORM="linux/amd64"

RELAY_IMAGE="scsibug/nostr-rs-relay"
RELAY_NAME="nostr-relay"
RELAY_INTERNAL_PORT=8080
# El puerto del anfitrion NO es arbitrario: la imagen de Coracle trae
# VITE_DEFAULT_RELAYS=ws://localhost:8080 grabado en su bundle JavaScript en
# tiempo de compilacion. Publicarlo en otro puerto dejaria al relay fuera de
# la lista de relays del cliente.
RELAY_HOST_PORT=8080

CLIENT_IMAGE="bracr10/coracle"
CLIENT_NAME="coracle"
CLIENT_INTERNAL_PORT=80
CLIENT_HOST_PORT=8000

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.toml"
CONFIG_TARGET="/usr/src/app/config.toml"

PAUSE_SECONDS=3       # pausa fija tras arrancar cada contenedor
MAX_RETRIES=20        # sondeos adicionales de disponibilidad
RETRY_DELAY=1

# ---------------------------------------------------------------------------
# Utilidades de salida
# ---------------------------------------------------------------------------
info() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
ok()   { printf '\033[1;32m  OK\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m  !!\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$1" >&2; exit 1; }

# Espera activa: sondea una URL hasta que responda o se agoten los intentos.
wait_for_http() {
  local url="$1" label="$2" extra="${3:-}"
  local i
  for ((i = 1; i <= MAX_RETRIES; i++)); do
    if [[ -n "$extra" ]]; then
      curl -sf -H "$extra" -o /dev/null "$url" && { ok "$label responde en $url"; return 0; }
    else
      curl -sf -o /dev/null "$url" && { ok "$label responde en $url"; return 0; }
    fi
    sleep "$RETRY_DELAY"
  done
  warn "$label no respondio tras $((MAX_RETRIES * RETRY_DELAY))s en $url"
  return 1
}

# ---------------------------------------------------------------------------
# 0. Comprobaciones previas
# ---------------------------------------------------------------------------
info "Comprobando requisitos previos"

command -v docker >/dev/null 2>&1 \
  || die "Docker no esta instalado o no esta en el PATH."

docker info >/dev/null 2>&1 \
  || die "El daemon de Docker no responde. Abre Docker Desktop y reintenta."
ok "Daemon de Docker activo"

[[ -f "$CONFIG_FILE" ]] \
  || die "No se encontro config.toml en ${SCRIPT_DIR}."
ok "config.toml encontrado"

# ---------------------------------------------------------------------------
# 1. Red
# ---------------------------------------------------------------------------
info "Creando la red '${NETWORK}'"

if docker network inspect "$NETWORK" >/dev/null 2>&1; then
  ok "La red '${NETWORK}' ya existia, se reutiliza"
else
  docker network create "$NETWORK" >/dev/null
  ok "Red '${NETWORK}' creada"
fi

# ---------------------------------------------------------------------------
# 2. Descarga de imagenes
# ---------------------------------------------------------------------------
info "Descargando imagenes (plataforma ${PLATFORM})"

docker pull --platform "$PLATFORM" "$RELAY_IMAGE"
docker pull --platform "$PLATFORM" "$CLIENT_IMAGE"
ok "Imagenes disponibles en local"

# ---------------------------------------------------------------------------
# 3. Relay
# ---------------------------------------------------------------------------
info "Levantando el relay '${RELAY_NAME}'"

docker run -d \
  --name "$RELAY_NAME" \
  --network "$NETWORK" \
  --platform "$PLATFORM" \
  -p "${RELAY_HOST_PORT}:${RELAY_INTERNAL_PORT}" \
  -v "${CONFIG_FILE}:${CONFIG_TARGET}:ro" \
  "$RELAY_IMAGE" >/dev/null

ok "Contenedor '${RELAY_NAME}' creado"

# Un contenedor recien creado no responde de inmediato.
info "Esperando ${PAUSE_SECONDS}s a que el relay arranque"
sleep "$PAUSE_SECONDS"
wait_for_http "http://localhost:${RELAY_HOST_PORT}" "Relay" "Accept: application/nostr+json" || true

# ---------------------------------------------------------------------------
# 4. Cliente web
# ---------------------------------------------------------------------------
info "Levantando el cliente '${CLIENT_NAME}'"

docker run -d \
  --name "$CLIENT_NAME" \
  --network "$NETWORK" \
  --platform "$PLATFORM" \
  -p "${CLIENT_HOST_PORT}:${CLIENT_INTERNAL_PORT}" \
  "$CLIENT_IMAGE" >/dev/null

ok "Contenedor '${CLIENT_NAME}' creado"

info "Esperando ${PAUSE_SECONDS}s a que el cliente arranque"
sleep "$PAUSE_SECONDS"
wait_for_http "http://localhost:${CLIENT_HOST_PORT}" "Cliente" || true

# ---------------------------------------------------------------------------
# 5. Resumen
# ---------------------------------------------------------------------------
echo
info "Estado de los contenedores"
docker ps --filter "name=${RELAY_NAME}" --filter "name=${CLIENT_NAME}" \
  --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'

echo
info "Descripcion publicada por el relay (NIP-11)"
curl -s -H "Accept: application/nostr+json" "http://localhost:${RELAY_HOST_PORT}" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print("  name        :", d.get("name")); print("  description :", d.get("description"))' \
  2>/dev/null || warn "No se pudo leer el documento NIP-11"

echo
printf '\033[1;32mDespliegue completado.\033[0m\n'
printf '  Cliente web : http://localhost:%s\n' "$CLIENT_HOST_PORT"
printf '  Relay       : ws://localhost:%s\n' "$RELAY_HOST_PORT"
printf '\n  Evidencia: abre el cliente, entra a Relays en la barra izquierda,\n'
printf '  localiza el relay de localhost y pulsa Info.\n'
