#!/usr/bin/env bash
# generate-env.sh
#
# Gera o arquivo envs/.env do repositório geonode-cluster combinando:
#   1. IPs das instâncias (lidos do terraform output -json)
#   2. Senhas, nomes, portas e configurações do envs/.env deste projeto
#
# Pré-requisito: terraform apply já foi executado com sucesso.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/envs/.env"
TF_DIR="${ROOT_DIR}/terraform"
REPO_DIR="${ROOT_DIR}/geonode-cluster"
OUTPUT_ENV="${REPO_DIR}/envs/.env"

# ── Verificações ───────────────────────────────────────────

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "✗ ${ENV_FILE} não encontrado. Execute: cp envs/.env.sample envs/.env"
  exit 1
fi

if [[ ! -d "${REPO_DIR}" ]]; then
  echo "✗ Diretório ${REPO_DIR} não encontrado."
  echo "  Execute bootstrap.sh ou clone o repositório primeiro."
  exit 1
fi

# ── Carrega nosso .env ─────────────────────────────────────
set -o allexport
# shellcheck disable=SC1090
source <(grep -v '^\s*#' "${ENV_FILE}" | grep -v '^\s*$')
set +o allexport

# ── Lê outputs do Terraform ────────────────────────────────
echo "→ Lendo outputs do Terraform..."
cd "${TF_DIR}"

TF_OUTPUT=$(terraform output -json 2>/dev/null) || {
  echo "✗ Falha ao ler terraform output. O terraform apply foi executado?"
  exit 1
}

tf_get() {
  echo "${TF_OUTPUT}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
key = '${1}'
val = data.get(key, {}).get('value')
print(val if val is not None else '')
"
}

TF_IP_DB=$(tf_get "ip_db")
TF_IP_GEONODE=$(tf_get "ip_geonode")
TF_IP_GS_WRITE=$(tf_get "ip_geoserver_write")
TF_IP_GS_READ_1=$(tf_get "ip_geoserver_read_1")
TF_IP_GS_READ_2=$(tf_get "ip_geoserver_read_2")
TF_IP_HAPROXY_1=$(tf_get "ip_haproxy_1")
TF_IP_HAPROXY_2=$(tf_get "ip_haproxy_2")
TF_IP_VIP=$(tf_get "ip_haproxy_vip")
TF_FIP=$(tf_get "floating_ip_vip")

# Hostname público: FIP se existir, caso contrário VIP privado
GEONODE_PUBLIC_IP="${TF_FIP:-${TF_IP_VIP}}"

# Permite sobrescrever via .env
EFFECTIVE_HOSTNAME="${GEONODE_HOSTNAME:-${GEONODE_PUBLIC_IP}}"

echo "→ Gerando ${OUTPUT_ENV}..."
mkdir -p "$(dirname "${OUTPUT_ENV}")"

cat > "${OUTPUT_ENV}" <<EOF
############################################################
# .env — geonode-cluster
# Gerado automaticamente por scripts/generate-env.sh
# Baseado em: ${ENV_FILE}
# Branch implantado: ${GEONODE_BRANCH:-main}
# Gerado em: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
#
# NÃO edite manualmente — edite envs/.env no projeto
# geonode-openstack-deploy e execute make generate-env.
############################################################

# ── Modo de deploy ────────────────────────────────────────
DEPLOY_MODE=production

# ── IPs das instâncias ────────────────────────────────────
IP_DB=${TF_IP_DB}
IP_GEONODE=${TF_IP_GEONODE}
IP_GEOSERVER_WRITE=${TF_IP_GS_WRITE}
IP_GEOSERVER_READ_1=${TF_IP_GS_READ_1}
IP_GEOSERVER_READ_2=${TF_IP_GS_READ_2}
IP_HAPROXY_1=${TF_IP_HAPROXY_1}
IP_HAPROXY_2=${TF_IP_HAPROXY_2}
HAPROXY_VIP=${TF_IP_VIP}
HAPROXY_VIP_PROD=${TF_IP_VIP}

# Floating IP público (vazio se create_floating_ip_for_vip = false)
FLOATING_IP_VIP=${TF_FIP}

# ── GeoNode — hostname público ────────────────────────────
# Hostname público para o server_name do Nginx
GEONODE_PUBLIC_HOSTNAME=${TF_FIP:-${TF_IP_VIP}}
GEONODE_HOSTNAME=${EFFECTIVE_HOSTNAME}
GEONODE_SITE_URL=http://${EFFECTIVE_HOSTNAME}

# ── Banco de dados ────────────────────────────────────────
DB_HOST=${TF_IP_DB}
DB_PORT=${DB_PORT:-5432}
GEONODE_DB_NAME=${GEONODE_DB_NAME:-geonode}
GEONODE_DB_USER=${GEONODE_DB_USER:-geonode}
GEONODE_DB_PASSWORD=${GEONODE_DB_PASSWORD}
GEODATA_DB_NAME=${GEODATA_DB_NAME:-geonode_data}
GEODATA_DB_USER=${GEODATA_DB_USER:-geonode_data}
GEODATA_DB_PASSWORD=${GEODATA_DB_PASSWORD}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# ── GeoNode — aplicação Django ────────────────────────────
GEONODE_ADMIN_USER=${GEONODE_ADMIN_USER:-admin}
GEONODE_ADMIN_PASSWORD=${GEONODE_ADMIN_PASSWORD}
GEONODE_ADMIN_EMAIL=${GEONODE_ADMIN_EMAIL:-admin@example.com}
DJANGO_SECRET_KEY=${DJANGO_SECRET_KEY}
GEONODE_PORT=${GEONODE_PORT:-8000}

# ── GeoServer ─────────────────────────────────────────────
GEOSERVER_ADMIN_USER=${GEOSERVER_ADMIN_USER:-admin}
GEOSERVER_ADMIN_PASSWORD=${GEOSERVER_ADMIN_PASSWORD}
GEOSERVER_PORT=${GEOSERVER_PORT:-8080}
GEOSERVER_JMS_PORT=${GEOSERVER_JMS_PORT:-61661}

# NFS — servidor é o geoserver-write
NFS_SERVER_IP=${TF_IP_GS_WRITE}
NFS_EXPORT_PATH=${NFS_EXPORT_PATH:-/opt/geoserver_data}
NFS_MOUNT_PATH=${NFS_MOUNT_PATH:-/opt/geoserver_data}

# ── HAProxy / Keepalived ──────────────────────────────────
HAPROXY_STATS_PORT=${HAPROXY_STATS_PORT:-8404}
HAPROXY_STATS_USER=${HAPROXY_STATS_USER:-haproxy}
HAPROXY_STATS_PASSWORD=${HAPROXY_STATS_PASSWORD}
HAPROXY_HTTP_PORT=${HAPROXY_HTTP_PORT:-80}
HAPROXY_HTTPS_PORT=${HAPROXY_HTTPS_PORT:-443}
KEEPALIVED_INTERFACE=${KEEPALIVED_INTERFACE:-ens3}
KEEPALIVED_ROUTER_ID=${KEEPALIVED_ROUTER_ID:-51}
EOF

echo "✔ ${OUTPUT_ENV} gerado com sucesso."
echo ""
echo "  Branch  : ${GEONODE_BRANCH:-main}"
echo "  Hostname: ${EFFECTIVE_HOSTNAME}"
echo "  DB      : ${TF_IP_DB}"
echo "  GeoNode : ${TF_IP_GEONODE}"
echo "  GS Write: ${TF_IP_GS_WRITE}"
echo "  GS Read : ${TF_IP_GS_READ_1} / ${TF_IP_GS_READ_2}"
echo "  HAProxy : ${TF_IP_HAPROXY_1} (MASTER) / ${TF_IP_HAPROXY_2} (BACKUP)"
echo "  VIP     : ${TF_IP_VIP}  FIP: ${TF_FIP:-n/a}"
