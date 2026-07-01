#!/usr/bin/with-contenv bash
# Provisioning desatendido y GENÉRICO de OpenClaw. Lo corre el oneshot s6
# init-openclaw-provision en cada boot (idempotente vía .setup-done).
#
# Análogo a hermes-provision.sh de hermes-sandbox. Vive en /config (bind mount
# de webtop) porque webtop define HOME=/config para el usuario abc (uid 1000).
# El wrapper (s6-init-openclaw-provision-run) invoca este script via
# `runuser -u abc --` — corre como abc desde el inicio, así que NO usamos
# runuser/su/s6-setuidgid acá (todos requieren root o capabilities que
# rootless podman no concede de forma estable).
#
# Filosofía: 100% agnóstico de provider. NO forzamos provider ni modelo.
# Aplicamos SOLO los overrides que el usuario pase por env vars. Lo no
# especificado queda en el default de OpenClaw. Sirve igual para LM Studio/
# Ollama local (gratis) o Claude/OpenAI/MiniMax/Z.AI (con tu API key).
#
# Convención de env vars (se pasan vía env_file .env del compose):
#   OPENCLAW_AUTH_CHOICE=<provider>             shortcut: corre `openclaw onboard`
#                                              --non-interactive con el provider
#                                              apropiado. Si está definida hace
#                                              TODO el setup (workspace, gateway,
#                                              provider, secretos, daemon-mode).
#                                              Valores: lmstudio|ollama|apiKey|
#                                              openai-api-key|zai-api-key|
#                                              gemini-api-key|mistral-api-key|...
#   OPENCLAW_CFG__<dotted.path>=valor  ->  `openclaw config set <path> <valor>`
#       ej: OPENCLAW_CFG__agent__model=qwen3.5:27b  ->  agent.model=qwen3.5:27b
#       doble guion bajo "__" = punto. Se aplica DESPUÉS de onboard.
#   OPENCLAW_ENV__<NAME>=valor        ->  escribe NAME=valor en ~/.openclaw/.env
#       ej: OPENCLAW_ENV__TELEGRAM_BOT_TOKEN=xxx    ->  TELEGRAM_BOT_TOKEN=xxx
#       Para secretos adicionales que el onboarding no cubre.
#
# Idempotencia: sentinela /config/.openclaw/.setup-done. Borrar la sentinela +
# recrear el contenedor reaplica TODO.
set -u
set -o pipefail

CONFIG_HOME=/config
export HOME="$CONFIG_HOME"
OPENCLAW_BIN=/usr/local/bin/openclaw
OPENCLAW_HOME="$CONFIG_HOME/.openclaw"
SETUP_DONE="$OPENCLAW_HOME/.setup-done"
ENVFILE="$OPENCLAW_HOME/.env"
LOG="$OPENCLAW_HOME/provision.log"

mkdir -p "$OPENCLAW_HOME"

log() { echo "[provision] $*" | tee -a "$LOG"; }

# 0) ¿Ya provisionado? Sentinela manda.
if [ -f "$SETUP_DONE" ]; then
    log "ya provisionado (sentinela presente), nada que hacer"
    exit 0
fi

# 1) Si OPENCLAW_AUTH_CHOICE está definida, corremos `openclaw onboard`
#    --non-interactive para hacer TODO el setup pesado (workspace,
#    gateway.mode=local, provider, secretos via --secret-input-mode,
#    --skip-bootstrap para no crear AGENTS.md/SOUL.md innecesarios).
if [ -n "${OPENCLAW_AUTH_CHOICE:-}" ]; then
    log "OPENCLAW_AUTH_CHOICE=${OPENCLAW_AUTH_CHOICE} — corriendo onboard unattended"

    # Args base, comunes a todos los providers
    ONBOARD_ARGS=(
        --non-interactive
        --mode local
        --gateway-port "${OPENCLAW_GATEWAY_PORT:-18789}"
        --gateway-bind "${OPENCLAW_GATEWAY_BIND:-loopback}"
        --accept-risk
        --skip-health        # no esperamos al gateway aquí; s6 lo arranca
        --skip-bootstrap     # no crear AGENTS.md/SOUL.md/IDENTITY.md por default
    )

    # Gateway token: si está definido, lo pasamos al onboard (lo escribe en
    # openclaw.json como gateway.auth.token). Si no, dejamos que onboard
    # genere uno (y queda en openclaw.json).
    if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
        ONBOARD_ARGS+=( --gateway-auth token --gateway-token "$OPENCLAW_GATEWAY_TOKEN" )
    else
        ONBOARD_ARGS+=( --gateway-auth token )  # genera token automatico
    fi

    case "$OPENCLAW_AUTH_CHOICE" in
        lmstudio)
            # LM Studio (local, gratis, sin API key real)
            ONBOARD_ARGS+=(
                --auth-choice lmstudio
                --custom-base-url "${OPENCLAW_CUSTOM_BASE_URL:-http://127.0.0.1:1234/v1}"
                --custom-model-id "${OPENCLAW_CUSTOM_MODEL_ID:-google/gemma-4-e4b}"
                --lmstudio-api-key "${OPENCLAW_LMSTUDIO_API_KEY:-lm-studio}"
            )
            ;;
        ollama)
            # Ollama (local, gratis, sin API key)
            ONBOARD_ARGS+=(
                --auth-choice ollama
                --custom-base-url "${OPENCLAW_CUSTOM_BASE_URL:-http://127.0.0.1:11434}"
                --custom-model-id "${OPENCLAW_CUSTOM_MODEL_ID:-qwen3.5:27b}"
            )
            ;;
        apiKey|anthropic-api-key)
            : "${OPENCLAW_ANTHROPIC_API_KEY:?OPENCLAW_ANTHROPIC_API_KEY requerido para auth-choice=$OPENCLAW_AUTH_CHOICE}"
            ONBOARD_ARGS+=(
                --auth-choice apiKey
                --anthropic-api-key "$OPENCLAW_ANTHROPIC_API_KEY"
                --secret-input-mode plaintext
            )
            ;;
        openai-api-key)
            : "${OPENCLAW_OPENAI_API_KEY:?OPENCLAW_OPENAI_API_KEY requerido para auth-choice=$OPENCLAW_AUTH_CHOICE}"
            ONBOARD_ARGS+=(
                --auth-choice openai-api-key
                --openai-api-key "$OPENCLAW_OPENAI_API_KEY"
                --secret-input-mode plaintext
            )
            ;;
        zai-api-key)
            : "${OPENCLAW_ZAI_API_KEY:?OPENCLAW_ZAI_API_KEY requerido}"
            ONBOARD_ARGS+=( --auth-choice zai-api-key --zai-api-key "$OPENCLAW_ZAI_API_KEY" --secret-input-mode plaintext )
            ;;
        gemini-api-key)
            : "${OPENCLAW_GEMINI_API_KEY:?OPENCLAW_GEMINI_API_KEY requerido}"
            ONBOARD_ARGS+=( --auth-choice gemini-api-key --gemini-api-key "$OPENCLAW_GEMINI_API_KEY" --secret-input-mode plaintext )
            ;;
        mistral-api-key)
            : "${OPENCLAW_MISTRAL_API_KEY:?OPENCLAW_MISTRAL_API_KEY requerido}"
            ONBOARD_ARGS+=( --auth-choice mistral-api-key --mistral-api-key "$OPENCLAW_MISTRAL_API_KEY" --secret-input-mode plaintext )
            ;;
        skip)
            # Sin auth — útil para dev/sandbox. gateway.mode=local igual se escribe.
            log "OPENCLAW_AUTH_CHOICE=skip — onboard sin auth (modo dev)"
            ONBOARD_ARGS+=( --auth-choice skip )
            ;;
        *)
            log "AVISO: OPENCLAW_AUTH_CHOICE='$OPENCLAW_AUTH_CHOICE' no reconocido, pasando literal a --auth-choice"
            ONBOARD_ARGS+=( --auth-choice "$OPENCLAW_AUTH_CHOICE" )
            ;;
    esac

    log "onboard args: ${ONBOARD_ARGS[*]}"
    # PIPESTATUS[0] = exit code de onboard (no de tee, gracias a pipefail).
    if "$OPENCLAW_BIN" onboard "${ONBOARD_ARGS[@]}" 2>&1 | tee -a "$LOG"; then
        log "onboard OK"
    else
        rc=${PIPESTATUS[0]}
        log "onboard FALLÓ (exit=$rc). El provider puede estar unreachable o faltan secretos."
        log "Causas típicas: LM Studio/Ollama no está corriendo en el host, o falta API key para el provider elegido."
        log "El gateway NO arrancará hasta que arregles y reproceses (ver README 'Reprovisionar tras cambiar valores')."
        log "NO toco la sentinela — gateway quedará esperando. Salgo con error para que s6 NO marque el provision como exitoso."
        exit "$rc"
    fi
fi

# 2) Overrides arbitrarios de openclaw.json: cualquier env var OPENCLAW_CFG__*
#    Doble "__" = ".". Se aplica DESPUÉS de onboard (onboard pisa sus propias
#    claves; OPENCLAW_CFG__* gana).
log "aplicando overrides OPENCLAW_CFG__*..."
while IFS= read -r var; do
    case "$var" in
        OPENCLAW_CFG__*)
            key="${var#OPENCLAW_CFG__}"      # agent__model
            key="${key//__/.}"               # agent.model
            val="${!var}"
            [ -z "$val" ] && continue
            log "  config set ${key}"
            "$OPENCLAW_BIN" config set "$key" "$val" 2>&1 | tee -a "$LOG" || \
                log "  WARN: config set ${key} falló (puede que la clave no exista en el schema; ignora)"
            ;;
    esac
done < <(compgen -e)

# 3) Secretos/URLs adicionales en ~/.openclaw/.env: cualquier OPENCLAW_ENV__*
#    Idempotente: borra la línea previa y reescribe.
log "escribiendo ~/.openclaw/.env..."
while IFS= read -r var; do
    case "$var" in
        OPENCLAW_ENV__*)
            key="${var#OPENCLAW_ENV__}"      # TELEGRAM_BOT_TOKEN
            val="${!var}"
            [ -z "$val" ] && continue
            sed -i "/^[[:space:]]*#\?[[:space:]]*${key}=/d" "$ENVFILE" 2>/dev/null || true
            printf '%s\n' "${key}=${val}" >> "$ENVFILE"
            log "  ${key}=***"
            ;;
    esac
done < <(compgen -e)

# 4) Sentinel. NO fallamos si algo de arriba falló — el gateway igual puede
#    arrancar (con config parcial) y el usuario puede intervenir.
touch "$SETUP_DONE"
log "listo — sentinel en $SETUP_DONE. Gateway arrancará a continuación."

# 5) Canal Telegram unattended (opcional, solo si OPENCLAW_ENV__TELEGRAM_BOT_TOKEN).
#    Corre ANTES de que el gateway arranque (gateway espera sentinela), así
#    que al levantarse ya encuentra el canal configurado — sin necesidad de
#    reiniciarlo a mano. Idempotente: si el canal ya existe, channels add
#    falla pero no bloqueamos (ya está configurado).
if [ -n "${OPENCLAW_ENV__TELEGRAM_BOT_TOKEN:-}" ]; then
    log "configurando canal Telegram unattended..."
    if "$OPENCLAW_BIN" channels add --channel telegram --token "${OPENCLAW_ENV__TELEGRAM_BOT_TOKEN}" 2>&1 | tee -a "$LOG"; then
        log "  channels add telegram OK"
    else
        # Si ya existe, channels add puede fallar con mensaje "already
        # configured". Miramos las últimas líneas del log para detectarlo.
        if tail -5 "$LOG" | grep -qiE '(already|existe|exists|duplicate)'; then
            log "  canal Telegram ya estaba configurado (idempotente)"
        else
            log "  WARN: channels add telegram falló — gateway arrancará sin Telegram"
        fi
    fi

    # Allowlist (opcional): OPENCLAW_ENV__TELEGRAM_ALLOWED_USERS="8414925941,1234567"
    if [ -n "${OPENCLAW_ENV__TELEGRAM_ALLOWED_USERS:-}" ]; then
        # Convierte "8414925941,1234567" -> ["8414925941","1234567"] (JSON5).
        # sed envuelve cada run no-coma en comillas; luego bracketeamos.
        JSON_USERS='['"$(printf '%s' "${OPENCLAW_ENV__TELEGRAM_ALLOWED_USERS}" | sed 's/[^,]*/"&"/g')"']'
        log "  allowlist: $JSON_USERS"
        "$OPENCLAW_BIN" config set channels.telegram.dmPolicy allowlist 2>&1 | tee -a "$LOG" \
            || log "  WARN: dmPolicy=allowlist falló"
        "$OPENCLAW_BIN" config set channels.telegram.allowFrom "$JSON_USERS" 2>&1 | tee -a "$LOG" \
            || log "  WARN: allowFrom falló"
    fi
    log "Telegram listo"
fi