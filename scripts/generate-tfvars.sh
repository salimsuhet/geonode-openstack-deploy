#!/usr/bin/env bash
# generate-tfvars.sh
# Gera terraform/terraform.tfvars a partir do envs/.env do projeto.
# Chamado automaticamente pelo bootstrap.sh antes do terraform apply.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/envs/.env"
TFVARS_FILE="${ROOT_DIR}/terraform/terraform.tfvars"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "✗ Arquivo ${ENV_FILE} não encontrado."
  echo "  Execute: cp envs/.env.sample envs/.env && edite o arquivo."
  exit 1
fi

# Carrega variáveis do .env (ignora comentários e linhas vazias)
# shellcheck disable=SC1090
set -o allexport
source <(grep -v '^\s*#' "${ENV_FILE}" | grep -v '^\s*$')
set +o allexport

echo "→ Gerando ${TFVARS_FILE}..."

cat > "${TFVARS_FILE}" <<EOF
# Gerado automaticamente por scripts/generate-tfvars.sh
# NÃO edite manualmente — edite envs/.env

os_auth_url             = "${OS_AUTH_URL}"
os_project_name         = "${OS_PROJECT_NAME}"
os_username             = "${OS_USERNAME}"
os_password             = "${OS_PASSWORD}"
os_region_name          = "${OS_REGION_NAME:-RegionOne}"
os_private_network_name = "${OS_PRIVATE_NETWORK_NAME}"
os_private_subnet_name  = "${OS_PRIVATE_SUBNET_NAME}"
os_provider_network     = "${OS_PROVIDER_NETWORK:-provider-network}"
os_image_name           = "${OS_IMAGE_NAME:-ubuntu-24.04}"

flavor_db               = "${FLAVOR_DB:-m1.large}"
flavor_geonode          = "${FLAVOR_GEONODE:-m1.large}"
flavor_geoserver_write  = "${FLAVOR_GEOSERVER_WRITE:-m1.large}"
flavor_geoserver_read   = "${FLAVOR_GEOSERVER_READ:-m1.medium}"
flavor_haproxy          = "${FLAVOR_HAPROXY:-m1.small}"

ip_db                   = "${IP_DB:-192.168.1.100}"
ip_geonode              = "${IP_GEONODE:-192.168.1.101}"
ip_geoserver_write      = "${IP_GEOSERVER_WRITE:-192.168.1.102}"
ip_geoserver_read_1     = "${IP_GEOSERVER_READ_1:-192.168.1.103}"
ip_geoserver_read_2     = "${IP_GEOSERVER_READ_2:-192.168.1.104}"
ip_haproxy_1            = "${IP_HAPROXY_1:-192.168.1.105}"
ip_haproxy_2            = "${IP_HAPROXY_2:-192.168.1.106}"
ip_haproxy_vip          = "${IP_HAPROXY_VIP:-192.168.1.107}"

create_floating_ip_for_vip = ${CREATE_FLOATING_IP_FOR_VIP:-true}

ssh_public_key_path     = "${SSH_PUBLIC_KEY_PATH:-~/.ssh/id_ed25519.pub}"
EOF

echo "✔ ${TFVARS_FILE} gerado."
