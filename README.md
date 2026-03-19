# openclaw-sandbox

Entorno de escritorio aislado en contenedor para ejecutar OpenClaw con soporte de automatizacion via Playwright.

## Que incluye la imagen

- **Debian Bookworm** como sistema base
- **XFCE4** como escritorio accesible via noVNC desde un navegador web
- **Node.js v24** con nvm (Node Version Manager)
- **OpenClaw** (CLI) para gestionar y ejecutar agentes
- **Playwright** con Chrome preinstalado para automatizacion de navegador
- **Playwright CLI** con skills instalados

## Requisitos

- **Podman** y **podman-compose** (recomendado, ya que Podman es rootless por defecto, lo que proporciona mayor seguridad al no requerir privilegios de root para ejecutar contenedores)
- Alternativamente **Docker** y **docker-compose** (los comandos son compatibles, reemplazando `podman` por `docker`)

## Configuracion

Copiar el archivo de ejemplo de variables de entorno y ajustarlo segun tus necesidades:

```bash
cp .env.example .env
```

Variables disponibles:
- `LOCALE` - Idioma y configuracion regional (por defecto `es_CL.UTF-8`)
- `TZ` - Zona horaria (por defecto `America/Santiago`)
- `VNC_PASSWORD` - Contrasena para acceder a noVNC (por defecto `agent`)
- `VNC_RESOLUTION` - Resolucion del escritorio virtual (por defecto `1280x720`)

## Inicio rapido

### 1. Construir y levantar el contenedor

```bash
podman compose up -d --build
```

La primera ejecucion tardara unos minutos porque:
- Construye la imagen de Debian con todas las dependencias
- Descarga e instala Node.js v24
- Instala Playwright y descarga Chrome

### 2. Acceder a noVNC

Abrir un navegador web y navegar a:

```
http://localhost:6080
```

Ingresar la contraseña VNC configurada en `.env` (por defecto `agent`).

### 3. Configurar OpenClaw

En el escritorio XFCE4:
1. Abrir una terminal (icono de terminal en la barra de tareas)
2. Ejecutar el comando de onboarding:

```bash
openclaw
```

Esto abrira un navegador para completar el proceso de autenticacion de OpenClaw.

### 4. Iniciar el gateway

Despues del onboarding, OpenClaw deberia iniciar el gateway automaticamente. Si no inicia:

1. Presionar `Ctrl+C` en la terminal
2. Ejecutar manualmente:

```bash
openclaw gateway
```

## Comandos utiles

### Ver logs en tiempo real

```bash
podman compose logs -f sandbox
```

### Entrar al contenedor

```bash
# Como root (por defecto)
podman compose exec sandbox bash

# Como usuario agent
podman compose exec --user agent sandbox bash
```

### Reiniciar desde cero (borra todos los datos)

Si necesitas reinstalar todo desde cero, incluyendo nvm, npm y OpenClaw:

```bash
podman compose down -v && podman compose up -d
```

Esto elimina los volúmenes y recrea el contenedor, ejecutando nuevamente el entrypoint.

### Detener el contenedor

```bash
podman compose down
```

### Reconstruir la imagen

Si haces cambios al `Containerfile`:

```bash
podman compose up -d --build
```

## Estructura de directorios persistentes

Los siguientes directorios se mantienen entre reinicios gracias a volúmenes:

- `/home/agent/.openclaw` - Configuracion y datos de OpenClaw
- `/home/agent/.playwright` - Datos de Playwright
- `/home/agent/.cache` - Cache de aplicaciones
- `/home/agent/.nvm` - Versiones de Node.js instaladas
- `/home/agent/.npm` - Paquetes npm globales
- `/home/agent/.config` - Configuracion del entorno de escritorio y setup.env

## Licencia

Este proyecto esta licenciado bajo la [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).

Puedes usar, modificar y distribuir este software libremente, siempre que incluyas el aviso de copyright original y un resumen de la licencia.
