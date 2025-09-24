#!/bin/bash
set -euo pipefail

DESTINATION=${1:-}
PORT=${2:-}
CHAT=${3:-}

if [[ -z "${DESTINATION}" || -z "${PORT}" || -z "${CHAT}" ]]; then
  echo "Uso: run.sh <DESTINATION> <HTTP_PORT> <LONGPOLLING_PORT>"
  echo "Ejemplo: run.sh odoo19-one 10019 20019"
  exit 1
fi

# ==== Config del repo ====
REPO_OWNER="RamiroHernandezB"
REPO_NAME="odoo-19-docker-compose"
REPO_HTTPS="https://github.com/${REPO_OWNER}/${REPO_NAME}.git"
BRANCH="${BRANCH:-main}"

# 1) Clonar plantilla Odoo 19 (privado con GH_TOKEN o público sin token)
if [[ -n "${GH_TOKEN:-}" ]]; then
  echo ">> Clonando repo privado con GH_TOKEN..."
  git -c http.extraheader="Authorization: Bearer ${GH_TOKEN}" \
      clone --depth=1 --branch "$BRANCH" "$REPO_HTTPS" "$DESTINATION"
else
  echo ">> Clonando repo público (sin GH_TOKEN)..."
  git clone --depth=1 --branch "$BRANCH" "$REPO_HTTPS" "$DESTINATION"
fi

rm -rf "$DESTINATION/.git"

# 2) Crear directorios necesarios
mkdir -p "$DESTINATION/postgresql" "$DESTINATION/odoo-data" "$DESTINATION/addons"

# 3) Dueños y permisos (seguro)
sudo chown -R "$USER:$USER" "$DESTINATION"
sudo chmod -R 700 "$DESTINATION"

# 4) Ajuste inotify en Linux (omitir en macOS)
if [[ "${OSTYPE:-}" != "darwin"* ]]; then
  grep -qF "fs.inotify.max_user_watches" /etc/sysctl.conf || echo "fs.inotify.max_user_watches = 524288" | sudo tee -a /etc/sysctl.conf
  grep -qF "fs.inotify.max_user_instances" /etc/sysctl.conf || echo "fs.inotify.max_user_instances = 8192" | sudo tee -a /etc/sysctl.conf
  sudo sysctl -p
else
  echo "Running on macOS. Skipping inotify configuration."
fi

# 5) Reemplazar puertos placeholder 10019/20019 del docker-compose.yml
compose_file="$DESTINATION/docker-compose.yml"
if [[ ! -f "$compose_file" ]]; then
  echo "ERROR: No existe $compose_file"
  exit 1
fi

if [[ "${OSTYPE:-}" == "darwin"* ]]; then
  sed -i '' "s/10019/${PORT}/g" "$compose_file"
  sed -i '' "s/20019/${CHAT}/g" "$compose_file"
else
  sed -i "s/10019/${PORT}/g" "$compose_file"
  sed -i "s/20019/${CHAT}/g" "$compose_file"
fi

# 6) Permisos finales
find "$DESTINATION" -type f -exec chmod 644 {} \;
find "$DESTINATION" -type d -exec chmod 755 {} \;

# Asegurar ejecutable del entrypoint
if [[ -f "$DESTINATION/entrypoint.sh" ]]; then
  chmod +x "$DESTINATION/entrypoint.sh"
fi

# 7) Levantar servicios (docker compose v2/v1)
if ! is_present="$(type -p docker-compose)" || [[ -z "${is_present}" ]]; then
  docker compose -f "$compose_file" up -d
else
  docker-compose -f "$compose_file" up -d
fi

echo "Odoo 19 started at http://localhost:${PORT} | Master Password: minhng.info | Live chat port: ${CHAT}"
