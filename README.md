# openclaw-sandbox

Entorno Docker/Podman reproducible para correr el **[OpenClaw](https://github.com/openclaw/openclaw)** (asistente personal multi-canal) dentro de un escritorio XFCE accesible por navegador, basado en [`linuxserver/webtop`](https://docs.linuxserver.io/images/docker-webtop/) + s6-overlay.

El setup completo (instalación de OpenClaw, configuración de provider, credenciales y arranque del gateway) es **desatendido**: en el primer boot el contenedor se autoconfigura desde variables de entorno, sin asistentes interactivos. Arquitectura 1:1 con [`hermes-sandbox`](../hermes-sandbox).

No fuerza un provider fijo: aplica **solo** los overrides que pases por env vars (convención genérica `OPENCLAW_AUTH_CHOICE` + `OPENCLAW_CFG__*` / `OPENCLAW_ENV__*`). Es **agnóstico de provider** — sirve igual con un modelo local gratis (LM Studio, Ollama) o con un provider de pago (Claude, OpenAI, MiniMax, Z.AI).

## Arquitectura

| Componente | Rol |
|---|---|
| `linuxserver/webtop:debian-xfce` | Imagen base: escritorio XFCE servido por KasmVNC + noVNC (s6-overlay v3 como PID 1) |
| `init-openclaw-provision` (oneshot s6) | Primer boot: aplica provider + secretos desde env vars. Idempotente vía sentinela `/config/.openclaw/.setup-done` |
| `svc-openclaw-gateway` (longrun s6) | Corre `openclaw gateway run` en foreground, supervisado por s6 (auto-restart, arranca en boot). Depende del oneshot vía s6 + sentinel wait |
| `openclaw-provision.sh` | Corre `openclaw onboard --non-interactive --mode local` + apply CFG/ENV + configura canal Telegram unattended |

OpenClaw vive en `/config/.openclaw/` (workspace + `openclaw.json` + `.env`) y persiste vía el bind mount `./config:/config`.

## Prerrequisitos

- Docker + Docker Compose, o Podman + podman-compose
- Acceso a un provider de modelo (elige uno en `.env`): local gratis ([LM Studio](https://lmstudio.ai/), [Ollama](https://ollama.com/)) o de pago con tu API key (Claude, OpenAI, MiniMax, Z.AI)

## Configuración

Toda la configuración vive en `.env` (no se versiona — `.gitignore` cubre `.env`; hay un `.env.example` de referencia). El compose pasa **todo** `.env` al contenedor (`env_file`), así que agregas o quitas claves `OPENCLAW_*` sin tocar `compose.yaml`.

### Convenciones de env vars

Tres niveles, todos opcionales. Lo que no definas queda en el default de OpenClaw.

| Prefijo | Efecto | Regla de nombre |
|---|---|---|
| `OPENCLAW_AUTH_CHOICE=<provider>` | shortcut: corre `openclaw onboard --non-interactive` con los flags del provider. Hace TODO el setup (workspace, gateway.mode=local, provider, secretos) en una sola pasada | valores: `lmstudio`, `ollama`, `apiKey`, `openai-api-key`, `zai-api-key`, `gemini-api-key`, `mistral-api-key`, `skip` |
| `OPENCLAW_CFG__<path>=valor` | `openclaw config set <path> <valor>` (edita `openclaw.json`) | `__` = `.` ; `_` simple se conserva |
| `OPENCLAW_ENV__<NAME>=valor` | escribe `NAME=valor` en `~/.openclaw/.env` (secretos/URLs no cubiertos por onboard). Si es `TELEGRAM_BOT_TOKEN`, además configura el canal unattended (channels add + allowlist) | tal cual |

`agent.model` ilustra la regla de nombres: `OPENCLAW_CFG__agent__model` → `agent.model` (el `__` es `.`).

### Elegir provider

El sandbox es **agnóstico**: defines provider, modelo y credencial en `.env`.

| Provider | `OPENCLAW_AUTH_CHOICE` | API key env var | `base_url` default |
|---|---|---|---|
| LM Studio (local, gratis) | `lmstudio` | `OPENCLAW_LMSTUDIO_API_KEY` (cualquier valor) | `http://127.0.0.1:1234/v1` |
| Ollama (local, gratis) | `ollama` | — (ninguna) | `http://127.0.0.1:11434` |
| Claude / Anthropic | `apiKey` | `OPENCLAW_ANTHROPIC_API_KEY` | (default Anthropic) |
| OpenAI | `openai-api-key` | `OPENCLAW_OPENAI_API_KEY` | (default OpenAI) |
| Z.AI | `zai-api-key` | `OPENCLAW_ZAI_API_KEY` | (auto-detect) |
| Sin modelo (dev) | `skip` | — | — |

> **Local:** desde el contenedor, `127.0.0.1` apunta al contenedor, no al host. Para LM Studio/Ollama corriendo en tu máquina usa la IP LAN (ej. `http://192.168.1.18:1234/v1`). El endpoint de LM Studio debe terminar en `/v1`.

Ejemplo mínimo (`.env`) con LM Studio local:

```dotenv
# Webtop
TZ=America/Santiago
TITLE=OpenClaw Agent
CUSTOM_USER=patricio
PASSWORD=cambia_esto

# Provider
OPENCLAW_AUTH_CHOICE=lmstudio
OPENCLAW_CUSTOM_BASE_URL=http://127.0.0.1:1234/v1
OPENCLAW_CUSTOM_MODEL_ID=google/gemma-4-e4b
OPENCLAW_LMSTUDIO_API_KEY=lm-studio

# Telegram unattended (opcional)
OPENCLAW_ENV__TELEGRAM_BOT_TOKEN=123456:ABC...
OPENCLAW_ENV__TELEGRAM_ALLOWED_USERS=8414925941
```

Ver [`.env.example`](./.env.example) para los 6 providers + ejemplos de overrides.

## Uso

```bash
docker compose up -d --build
# (o: podman compose up -d --build)
```

Abre el escritorio en `http://localhost:3300` (contraseña: la de `PASSWORD` en `.env`). En el primer boot el provisioning instala/configura OpenClaw y arranca el gateway automáticamente (puede tardar unos minutos descargando Node + npm packages + ejecutando `openclaw onboard`).

Sigue el progreso con:

```bash
docker logs -f openclaw-webtop                                # log general (s6 + provisioner + gateway)
docker exec openclaw-webtop cat /config/.openclaw/provision.log    # log del provisioner
docker exec openclaw-webtop tail -f /run/service/svc-openclaw-gateway/log/current   # log del gateway
```

### Reinstalación limpia

```bash
docker compose down
sudo rm -rf ./config          # contiene archivos de root creados por el contenedor
docker compose up -d --build
```

Vuelve a quedar 100% configurado sin intervención. Los permisos del bind mount se autocorrigen en cada boot (`init-adduser` de linuxserver corre `lsiown abc:abc /config`).

### Reprovisionar tras cambiar valores

```bash
# edita .env, luego:
docker exec openclaw-webtop rm -f /config/.openclaw/.setup-done
docker compose up -d --force-recreate   # contenedor fresco → el oneshot reaplica openclaw.json/.env
```

`--force-recreate` garantiza que el gateway arranque de nuevo y cargue la config recién aplicada. Si en cambio solo editaste valores en caliente (sin recrear), reinicia el gateway:

```bash
docker exec openclaw-webtop s6-svc -r /run/service/svc-openclaw-gateway
```

## Gestión del gateway

El gateway corre como `svc-openclaw-gateway` en s6. Para controlarlo:

```bash
s6-svc -d /run/service/svc-openclaw-gateway   # detener
s6-svc -u /run/service/svc-openclaw-gateway   # iniciar
s6-svc -r /run/service/svc-openclaw-gateway   # reiniciar (tras editar openclaw.json/.env)
docker logs openclaw-webtop                    # ver logs
```

El binario de OpenClaw (en PATH para root y abc): `/usr/local/bin/openclaw`.

## Diagnóstico

Si el provisioning no completó (sentinela `.setup-done` ausente tras ~10 min), abre una terminal en el escritorio XFCE y revisa:

```bash
cat /config/.openclaw/provision.log
docker logs openclaw-webtop | grep -E 'openclaw|provision'
```

Causas típicas: sin red, falta `OPENCLAW_AUTH_CHOICE` en `.env`, falta la API key obligatoria para el provider elegido, o el provider local (LM Studio/Ollama) no está corriendo en el host.

## Notas de diseño (gotchas)

- **No se instala openclaw en runtime.** Node + openclaw se instalan en build (en `/usr/local`), persistentes en la imagen. La config persiste en `/config` (bind mount).
- **Gateway en foreground bajo s6.** OpenClaw no se "supervisa a sí mismo" en contenedor — s6 se encarga. Por eso el provisioner escribe `gateway.mode=local` (vía `onboard --mode local`) y el gateway usa `--allow-unconfigured` como red de seguridad.
- **`gateway.mode=local` no es opcional.** Sin esto, OpenClaw refuse-a arrancar el gateway (es un guard de seguridad). El provisioner lo escribe; si onboard falla, el gateway queda esperando sentinela (intencional, para que el usuario intervenga).
- **`--bind loopback` siempre.** En contenedor, OpenClaw cambia el bind default a `auto` (0.0.0.0) y refuse-a sin auth. Forzamos loopback porque el sandbox se accede solo via noVNC.
- **Telegram unattended es un bonus.** Si defines `OPENCLAW_ENV__TELEGRAM_BOT_TOKEN`, el provisioner configura el canal (channels add + allowlist + dmPolicy) ANTES de que el gateway arranque. No requiere reinicio manual.

## Licencia

[Apache License 2.0](./LICENSE).