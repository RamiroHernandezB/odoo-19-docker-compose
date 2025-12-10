#!/usr/bin/env bash
set -euo pipefail

ODOO_RC="${ODOO_RC:-/etc/odoo/odoo.conf}"

# Preferimos variables PG*, con fallback a las que ya usabas
DB_HOST="${PGHOST:-${HOST:-db}}"
DB_PORT="${PGPORT:-${PORT:-5432}}"
DB_USER="${PGUSER:-${USER:-odoo}}"
DB_PASSWORD="${PGPASSWORD:-${PASSWORD:-odoo19@2025}}"
DB_NAME="${PGDATABASE:-${POSTGRES_DB:-}}"

wait_for_db() {
  local host="$1" port="$2" timeout="${3:-30}" s=0
  echo "[entrypoint] Esperando a Postgres ${host}:${port} (timeout ${timeout}s)..."
  while ! (echo > /dev/tcp/${host}/${port}) >/dev/null 2>&1; do
    sleep 1; s=$((s+1))
    [ "$s" -ge "$timeout" ] && echo "[entrypoint] Timeout esperando a Postgres" && return 1
  done
  echo "[entrypoint] Postgres disponible."
}

# Construimos args de DB leyendo del conf si ya existen ahí
DB_ARGS=()
add_or_keep_conf() {
  local param="$1" value="$2"
  if [ -f "$ODOO_RC" ] && grep -q -E "^\s*${param}\s*=" "$ODOO_RC"; then
    value="$(awk -F= -v k="$param" '$1 ~ k {print $2}' "$ODOO_RC" | tr -d "\"[:space:]")"
  fi
  DB_ARGS+=("--${param}" "${value}")
}
add_or_keep_conf "db_host" "$DB_HOST"
add_or_keep_conf "db_port" "$DB_PORT"
add_or_keep_conf "db_user" "$DB_USER"
add_or_keep_conf "db_password" "$DB_PASSWORD"

# Odoo 19 NO acepta --db_name. Si hay nombre de BD, usar -d/--database
DBNAME_ARGS=()
if [ -n "${DB_NAME:-}" ]; then
  DBNAME_ARGS+=("-d" "$DB_NAME")
fi

# Requisitos de addons (opcional)
if [ -f /mnt/extra-addons/requirements.txt ]; then
  echo "[entrypoint] Instalando requirements de addons..."
  pip install --no-cache-dir -r /mnt/extra-addons/requirements.txt
fi

# Esperar DB
wait_for_db "$DB_HOST" "$DB_PORT" 30

# Compat: si primer arg es "--" o "odoo", lo ignoramos
if [[ "${1:-}" == "--" || "${1:-}" == "odoo" ]]; then
  shift || true
fi

# Si no pasaron args, usamos el conf
if [[ $# -eq 0 ]]; then
  set -- "-c" "$ODOO_RC"
fi

echo "[entrypoint] Lanzando Odoo: /opt/odoo/odoo/odoo-bin $* ${DB_ARGS[*]} ${DBNAME_ARGS[*]}"
exec /opt/odoo/odoo/odoo-bin "$@" "${DB_ARGS[@]}" "${DBNAME_ARGS[@]}"