#!/bin/bash
agent_home=/home/agent

# Cargar variables de estado si existen
if [ -f "$agent_home/.config/setup.env" ]; then
    source "$agent_home/.config/setup.env"
fi

# Instalar nvm y node si no está marcado como instalado
if [ "${nvm_installed}" != "true" ]; then
    su - agent -c '
    set -o pipefail
    mv /home/agent/.bashrc /home/agent/.bashrc.original
    touch /home/agent/.bash_env
    touch /home/agent/.bashrc
    echo ". /home/agent/.bash_env" > /home/agent/.bashrc
    cat /home/agent/.bashrc.original >> /home/agent/.bashrc
    rm -f /home/agent/.bashrc.original
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | PROFILE="/home/agent/.bash_env" bash
    source /home/agent/.bash_env
    echo "nvm_installed=true" >> "$agent_home/.config/setup.env"
    nvm install v24.10.0
    ' >> /var/log/entrypoint-setup.log 2>&1
fi

# Instalar paquetes npm globales si no están marcados como instalados
if [ "${npm_packages_installed}" != "true" ]; then
    su - agent -c '
    source /home/agent/.bash_env
    npm install -g openclaw@latest
    npm install -g @playwright/cli@latest
    playwright-cli install --skills
    echo "npm_packages_installed=true" >> "$agent_home/.config/setup.env"
    ' >> /var/log/entrypoint-setup.log 2>&1
fi

exec "$@"
