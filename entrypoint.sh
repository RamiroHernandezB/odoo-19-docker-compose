FROM python:3.12-slim

# Variables de entorno
ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Paquetes del sistema (sin wkhtmltopdf por apt) + cliente Postgres 18
RUN apt-get update && apt-get install -y --no-install-recommends \
    git build-essential \
    libxml2-dev libxslt1-dev libldap2-dev libsasl2-dev \
    libpq-dev libjpeg-dev libfreetype6-dev zlib1g-dev \
    nodejs npm \
    fontconfig libxrender1 libxext6 libx11-6 curl ca-certificates xz-utils \
    wget gnupg lsb-release \
 && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc \
      | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg \
 && echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends postgresql-client-18 \
 && rm -rf /var/lib/apt/lists/*

#Librerias para evitar error con QR
RUN apt-get update && apt-get install -y --no-install-recommends \
    libcairo2 \
    libcairo2-dev \
    pkg-config \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libpango1.0-dev \
 && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir pycairo
# Instalar wkhtmltopdf (Qt parcheado) para Debian 12/bookworm
RUN curl -fSL -o /tmp/wkhtmltox.deb \
      https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_amd64.deb \
 && apt-get update && apt-get install -y --no-install-recommends \
      libpng16-16 libjpeg62-turbo libx11-6 libxcb1 libxext6 libxrender1 libssl3 zlib1g \
 && dpkg -i /tmp/wkhtmltox.deb || apt-get -f install -y \
 && ln -sf /usr/local/bin/wkhtmltopdf /usr/bin/wkhtmltopdf \
 && ln -sf /usr/local/bin/wkhtmltoimage /usr/bin/wkhtmltoimage \
 && rm -rf /var/lib/apt/lists/* /tmp/wkhtmltox.deb

# Directorios y usuario
RUN mkdir -p /opt/odoo/custom-addons /var/lib/odoo /etc/odoo
WORKDIR /opt/odoo

# Clonar Odoo y fijarlo al commit
ARG ODOO_REPO=https://github.com/odoo/odoo.git
ARG ODOO_COMMIT=4688b037063b9c08151f4bde9d816165ba6b7576
RUN git clone --depth 1 ${ODOO_REPO} /opt/odoo/odoo \
 && cd /opt/odoo/odoo \
 && git fetch --depth 1 origin ${ODOO_COMMIT} \
 && git checkout ${ODOO_COMMIT}

# Requisitos Python del core
RUN pip install --no-cache-dir --upgrade pip setuptools wheel \
 && pip install --no-cache-dir -r /opt/odoo/odoo/requirements.txt

RUN pip uninstall -y reportlab \
 && pip install --no-cache-dir --no-binary=reportlab reportlab==4.1.0
# Entrypoint propio
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Usuario sin privilegios
RUN useradd -ms /bin/bash odoo \
 && chown -R odoo:odoo /opt/odoo /var/lib/odoo /etc/odoo /entrypoint.sh
USER odoo

ENV PATH="/home/odoo/.local/bin:${PATH}"

EXPOSE 8069 8072
ENTRYPOINT ["/entrypoint.sh"]
CMD ["odoo", "-c", "/etc/odoo/odoo.conf"]
root@saas1718:~/odoo19/cacep# 
root@saas1718:~/odoo19/cacep# 
root@saas1718:~/odoo19/cacep# 
root@saas1718:~/odoo19/cacep# cat entrypoint.sh 
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
        value="$(awk -F= -v k="$param" '
        /^[[:space:]]*[;#]/ {next}      # ignorar comentarios
        NF < 2 {next}                   # ignorar líneas sin "="
        {
        key=$1; val=$2
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
        if (key == k) { print val; exit }
     }
' "$ODOO_RC" | tr -d "\"")"
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