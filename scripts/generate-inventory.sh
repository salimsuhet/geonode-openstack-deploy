#!/usr/bin/env bash
# generate-inventory.sh
#
# Gera o inventário de produção do geonode-cluster
# (ansible/inventories/production/hosts.yml) a partir dos
# IPs fixos definidos em envs/.env + terraform outputs.
#
# Também garante que o group_vars de produção leia o .env
# correto (o gerado pelo generate-env.sh).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/envs/.env"
REPO_DIR="${ROOT_DIR}/geonode-cluster"
INVENTORY_DIR="${REPO_DIR}/ansible/inventories/production"
HOSTS_FILE="${INVENTORY_DIR}/hosts.yml"
GROUP_VARS_FILE="${INVENTORY_DIR}/group_vars/all.yml"

# ── Carrega .env ───────────────────────────────────────────
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "✗ ${ENV_FILE} não encontrado."
  exit 1
fi

set -o allexport
# shellcheck disable=SC1090
source <(grep -v '^\s*#' "${ENV_FILE}" | grep -v '^\s*$')
set +o allexport

# ── Lê IPs do Terraform ────────────────────────────────────
cd "${ROOT_DIR}/terraform"
TF_OUTPUT=$(terraform output -json 2>/dev/null) || {
  echo "✗ Falha ao ler terraform output."
  exit 1
}

tf_get() {
  echo "${TF_OUTPUT}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
val = data.get('${1}', {}).get('value')
print(val if val is not None else '')
"
}

IP_DB=$(tf_get "ip_db")
IP_GEONODE=$(tf_get "ip_geonode")
IP_GS_WRITE=$(tf_get "ip_geoserver_write")
IP_GS_READ_1=$(tf_get "ip_geoserver_read_1")
IP_GS_READ_2=$(tf_get "ip_geoserver_read_2")
IP_HAPROXY_1=$(tf_get "ip_haproxy_1")
IP_HAPROXY_2=$(tf_get "ip_haproxy_2")

SSH_KEY="${SSH_PRIVATE_KEY_PATH:-~/.ssh/id_ed25519}"
SSH_USER="${SSH_USER:-ubuntu}"

# ── Gera hosts.yml ─────────────────────────────────────────
echo "→ Gerando ${HOSTS_FILE}..."
mkdir -p "${INVENTORY_DIR}/group_vars"

cat > "${HOSTS_FILE}" <<EOF
---
# Gerado automaticamente por scripts/generate-inventory.sh
# Branch: ${GEONODE_BRANCH:-main} | $(date -u +"%Y-%m-%dT%H:%M:%SZ")

all:
  vars:
    ansible_user: ${SSH_USER}
    ansible_ssh_private_key_file: ${SSH_KEY}
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    deploy_env: production

  children:

    db:
      hosts:
        db:
          ansible_host: ${IP_DB}

    geonode:
      hosts:
        geonode:
          ansible_host: ${IP_GEONODE}

    geoserver_write:
      hosts:
        geoserver-write:
          ansible_host: ${IP_GS_WRITE}

    geoserver_read:
      hosts:
        geoserver-read-1:
          ansible_host: ${IP_GS_READ_1}
        geoserver-read-2:
          ansible_host: ${IP_GS_READ_2}

    geoserver:
      children:
        geoserver_write:
        geoserver_read:

    haproxy:
      hosts:
        haproxy-1:
          ansible_host: ${IP_HAPROXY_1}
          keepalived_state: MASTER
          keepalived_priority: 101
        haproxy-2:
          ansible_host: ${IP_HAPROXY_2}
          keepalived_state: BACKUP
          keepalived_priority: 100
EOF

# ── Gera group_vars/all.yml para produção ─────────────────
# Aponta para o .env gerado pelo generate-env.sh.
cat > "${GROUP_VARS_FILE}" <<EOF
---
# Gerado automaticamente — não edite manualmente.
# Carrega variáveis do .env via lookup('env', ...).
# O arquivo .env foi gerado por scripts/generate-env.sh.

# O geonode-cluster lê as variáveis de ambiente via lookup('env', ...).
# Para que isso funcione em produção, as variáveis devem estar
# exportadas no ambiente que executa o ansible-playbook.
# O bootstrap.sh faz esse export automaticamente.
#
# Se executar o ansible manualmente:
#   export \$(grep -v '^#' envs/.env | xargs)
#   ansible-playbook -i ansible/inventories/production/hosts.yml ansible/site.yml
EOF

echo "✔ Inventário gerado: ${HOSTS_FILE}"
echo "✔ group_vars gerado : ${GROUP_VARS_FILE}"
