# docker-ia-infra-bitcoin

Despliegue local de un **relay Nostr** ([`scsibug/nostr-rs-relay`](https://hub.docker.com/r/scsibug/nostr-rs-relay))
y un **cliente web** ([`bracr10/coracle`](https://hub.docker.com/r/bracr10/coracle)),
ambos en contenedores Docker conectados a una misma red.

El relay se personaliza mediante `config.toml` para que se anuncie con una
descripcion propia, visible desde el cliente.

---

## Requisitos previos

- **Docker Desktop instalado y en ejecucion.** Si el daemon esta apagado los
  scripts abortan con un mensaje explicito. Comprobarlo con `docker info`.
- **`curl`** y **`python3`**, usados por `deploy.sh` para verificar el estado
  del relay. Ambos vienen de serie en macOS.
- **Apple Silicon:** las dos imagenes solo publican variante `linux/amd64`.
  Los scripts pasan `--platform linux/amd64` y Docker Desktop las ejecuta
  emuladas. Funciona sin configuracion extra, solo arranca algo mas lento.

---

## Contenido del repositorio

| Archivo | Proposito |
|---|---|
| `deploy.sh` | Crea la red, descarga las imagenes y levanta ambos contenedores |
| `cleanup.sh` | Detiene y elimina los contenedores, y borra la red |
| `config.toml` | Configuracion del relay, con la descripcion personalizada |
| `README.md` | Este documento |

---

## Orden de ejecucion

Un archivo `.sh` recien creado no es ejecutable; sin este paso el sistema
responde `Permission denied`. Solo hace falta una vez:

```bash
chmod +x deploy.sh cleanup.sh
```

Desplegar:

```bash
./deploy.sh
```

Desmontar todo:

```bash
./cleanup.sh
```

`deploy.sh` falla si los contenedores ya existen. Para volver a empezar,
ejecutar siempre `./cleanup.sh` antes.

---

## Acceso

| Servicio | URL | Puertos |
|---|---|---|
| **Cliente web (Coracle)** | <http://localhost:8000> | `8000` -> `80` |
| **Relay (nostr-rs-relay)** | `ws://localhost:8080` | `8080` -> `8080` |

El puerto del cliente es libre; el del relay **no**. La imagen de Coracle
trae `VITE_DEFAULT_RELAYS=ws://localhost:8080` grabado en su bundle
JavaScript en tiempo de compilacion, asi que el relay debe quedar publicado
en el puerto `8080` del anfitrion para que el cliente lo encuentre solo.

---

## Verificar el resultado

### Desde el navegador (evidencia de la practica)

1. Abrir <http://localhost:8000>.
2. En la barra izquierda, entrar a **Relays**.
3. Localizar el relay correspondiente a `localhost`.
4. Pulsar **Info**.

Debe aparecer la descripcion definida en `config.toml`:

```
Relay local de practica para Docker - aobregon-dev
```

### Desde la terminal

El relay publica sus metadatos segun NIP-11. Es la via rapida para confirmar
que el `config.toml` se monto correctamente, sin depender del navegador:

```bash
curl -s -H "Accept: application/nostr+json" http://localhost:8080 | python3 -m json.tool
```

Si el campo `description` muestra `A newly created nostr-rs-relay`, el
montaje del archivo fallo.

Comprobar que ambos contenedores comparten la red:

```bash
docker network inspect nostr-net --format '{{range .Containers}}{{.Name}} {{end}}'
```

Tras la limpieza, comprobar que no queda nada:

```bash
docker ps -a
docker network ls
```

---

## Notas

- **Persistencia:** no se monta volumen para la base de datos. El relay corre
  como usuario `appuser` y un bind mount desde macOS provocaria un error de
  permisos al abrir SQLite. Los eventos viven dentro del contenedor y se
  pierden con `./cleanup.sh`, que es el comportamiento deseado en una practica.
- **La red Docker:** `deploy.sh` crea `nostr-net` y conecta ambos contenedores.
  Conviene saber que el trafico real entre cliente y relay no circula por esa
  red: Coracle se ejecuta en el navegador, de modo que el WebSocket sale desde
  la maquina anfitriona hacia el puerto publicado `8080`.
