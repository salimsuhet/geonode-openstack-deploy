#!/usr/bin/env bash
# bootstrap.sh
#
# Pipeline completo de provisionamento e deploy do GeoNode Cluster.
#
# Etapas executadas em ordem:
#   1. Validação de dependências e do .env
#   2. Geração do terraform.tfvars a partir do .env
#   3. terraform init + plan + apply (provisionamento das VMs)
#   4. Clone/atualização do repositório geonode-cluster no branch configurado
#   5. Geração do envs/.env para o geonode-cluster (generate-env.sh)
#   6. Geração do inventário Ansible de produção (generate-inventory.sh)
#   7. Exportação das variáveis de ambiente e execução do ansible-playbook
#
# Pré-requisitos no host controlador:
#   - Terraform >= 1.3
#   - Ansible >= 2.15
#   - python3 (para processar terraform output -json)
#   - git
#   - Conectividade SSH com as instâncias (via WireGuard do tenant)
#
# Uso:
#   ./scripts/bootstrap.sh                  # pipeline completo
#   ./scripts/bootstrap.sh --tf-only        # apenas Terraform
#   ./scripts/bootstrap.sh --ansible-only   # apenas Ansible (Terraform já aplicado)
#   ./scripts/bootstrap.sh --skip-tf        # pula Terraform (alias de --ansible-only)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${ROOT_DIR}/envs/.env"
TF_DIR="${ROOT_DIR}/terraform"
REPO_DIR="${ROOT_DIR}/geonode-cluster"

GEONODE_CLUSTER_REPO="https://github.com/salimsuhet/geonode-cluster.git"

# ── Flags ──────────────────────────────────────────────────
TF_ONLY=false
ANSIBLE_ONLY=false
AUTO_APPROVE=false

for arg in "$@"; do
  case "${arg}" in
    --tf-only)       TF_ONLY=true ;;
    --ansible-only)  ANSIBLE_ONLY=true ;;
    --skip-tf)       ANSIBLE_ONLY=true ;;
    --auto-approve)  AUTO_APPROVE=true ;;
    --help|-h)
      echo "Uso: $0 [--tf-only] [--ansible-only|--skip-tf] [--auto-approve]"
      exit 0
      ;;
  esac
done

# ── Cores ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; RESET='\033[0m'; BOLD='\033[1m'

info()    { echo -e "${BLUE}→${RESET} $*"; }
success() { echo -e "${GREEN}✔${RESET} $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET} $*"; }
error()   { echo -e "${RED}✗${RESET} $*" >&2; exit 1; }
section() { echo -e "\n${BOLD}════════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}  $*${RESET}"; \
            echo -e "${BOLD}════════════════════════════════════════${RESET}"; }

# ── 1. Validações ──────────────────────────────────────────
section "Etapa 1 — Validando dependências"

command -v terraform &>/dev/null || error "terraform não encontrado. Instale >= 1.3."
command -v ansible-playbook &>/dev/null || error "ansible-playbook não encontrado. Instale >= 2.15."
command -v git &>/dev/null || error "git não encontrado."
command -v python3 &>/dev/null || error "python3 não encontrado."

TF_VERSION=$(terraform version -json | python3 -c "import json,sys; print(json.load(sys.stdin)['terraform_version'])" 2>/dev/null || echo "unknown")
ANSIBLE_VERSION=$(ansible --version | head -1 | grep -oP '[\d.]+' | head -1)
info "terraform: ${TF_VERSION}  |  ansible: ${ANSIBLE_VERSION}"

if [[ ! -f "${ENV_FILE}" ]]; then
  error "${ENV_FILE} não encontrado.\n  Execute: cp envs/.env.sample envs/.env e edite o arquivo."
fi

# Carrega .env
set -o allexport
# shellcheck disable=SC1090
source <(grep -v '^\s*#' "${ENV_FILE}" | grep -v '^\s*$')
set +o allexport

# Valida campos obrigatórios
REQUIRED_VARS=(
  OS_AUTH_URL OS_PROJECT_NAME OS_USERNAME OS_PASSWORD
  OS_PRIVATE_NETWORK_NAME OS_PRIVATE_SUBNET_NAME
  GEONODE_DB_PASSWORD GEODATA_DB_PASSWORD POSTGRES_PASSWORD
  GEONODE_ADMIN_PASSWORD GEOSERVER_ADMIN_PASSWORD DJANGO_SECRET_KEY
)
MISSING=()
for v in "${REQUIRED_VARS[@]}"; do
  [[ -z "${!v:-}" ]] && MISSING+=("${v}")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
  error "Variáveis obrigatórias não definidas em envs/.env:\n  ${MISSING[*]}"
fi

GEONODE_BRANCH="${GEONODE_BRANCH:-main}"
success "Dependências e .env validados. Branch: ${GEONODE_BRANCH}"

# ── 2. Terraform ───────────────────────────────────────────
if [[ "${ANSIBLE_ONLY}" == "false" ]]; then
  section "Etapa 2 — Gerando terraform.tfvars"
  bash "${SCRIPT_DIR}/generate-tfvars.sh"
  success "terraform.tfvars gerado."

  section "Etapa 3 — Provisionando infraestrutura (Terraform)"
  cd "${TF_DIR}"

  info "terraform init..."
  terraform init -upgrade

  info "terraform plan..."
  terraform plan -var-file="terraform.tfvars" -out="${TF_DIR}/out.plan"

  if [[ "${AUTO_APPROVE}" == "false" ]]; then
    echo ""
    read -r -p "  Aplicar o plano acima? [s/N] " CONFIRM
    [[ "${CONFIRM}" =~ ^[sS]$ ]] || { warn "Aplicação cancelada."; exit 0; }
  fi

  info "terraform apply..."
  terraform apply "${TF_DIR}/out.plan"
  success "Infraestrutura provisionada."

  # Aguarda instâncias ficarem acessíveis via SSH
  section "Aguardando SSH nas instâncias"
  SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY_PATH:-~/.ssh/id_ed25519}"
  SSH_USER="${SSH_USER:-ubuntu}"
  WAIT_IPS=(
    "${IP_DB:-192.168.1.100}"
    "${IP_GEONODE:-192.168.1.101}"
    "${IP_GEOSERVER_WRITE:-192.168.1.102}"
    "${IP_GEOSERVER_READ_1:-192.168.1.103}"
    "${IP_GEOSERVER_READ_2:-192.168.1.104}"
    "${IP_HAPROXY_1:-192.168.1.105}"
    "${IP_HAPROXY_2:-192.168.1.106}"
  )
  for ip in "${WAIT_IPS[@]}"; do
    info "Aguardando SSH em ${ip}..."
    for i in $(seq 1 30); do
      if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
             -i "${SSH_PRIVATE_KEY}" "${SSH_USER}@${ip}" "echo ok" &>/dev/null; then
        success "  ${ip} acessível."
        break
      fi
      [[ "${i}" -eq 30 ]] && warn "  Timeout aguardando ${ip} — continuando mesmo assim."
      sleep 10
    done
  done
fi

if [[ "${TF_ONLY}" == "true" ]]; then
  success "Modo --tf-only: encerrando após Terraform."
  exit 0
fi

# ── 3. Clone do repositório ────────────────────────────────
section "Etapa 4 — Repositório geonode-cluster (branch: ${GEONODE_BRANCH})"

if [[ -d "${REPO_DIR}/.git" ]]; then
  info "Repositório já existe — atualizando para branch ${GEONODE_BRANCH}..."
  cd "${REPO_DIR}"
  git fetch origin
  git checkout "${GEONODE_BRANCH}"
  git pull origin "${GEONODE_BRANCH}"
else
  info "Clonando ${GEONODE_CLUSTER_REPO} (branch: ${GEONODE_BRANCH})..."
  git clone --branch "${GEONODE_BRANCH}" "${GEONODE_CLUSTER_REPO}" "${REPO_DIR}"
fi
success "Repositório em ${REPO_DIR} (branch: ${GEONODE_BRANCH})."

# ── 4. Gera .env do geonode-cluster ───────────────────────
section "Etapa 5 — Gerando envs/.env para geonode-cluster"
bash "${SCRIPT_DIR}/generate-env.sh"
success "envs/.env gerado em ${REPO_DIR}/envs/.env"

# ── 5. Gera inventário Ansible ─────────────────────────────
section "Etapa 6 — Gerando inventário Ansible de produção"
bash "${SCRIPT_DIR}/generate-inventory.sh"
success "Inventário gerado."

# ── 6. Instala dependências Ansible ───────────────────────
section "Etapa 7 — Instalando Ansible collections"
if [[ -f "${REPO_DIR}/ansible/requirements.yml" ]]; then
  ansible-galaxy collection install -r "${REPO_DIR}/ansible/requirements.yml"
  success "Collections instaladas."
else
  warn "ansible/requirements.yml não encontrado — pulando."
fi

# ── 7. Executa Ansible ────────────────────────────────────
section "Etapa 8 — Deploy com Ansible"

INVENTORY="${REPO_DIR}/ansible/inventories/production/hosts.yml"
PLAYBOOK="${REPO_DIR}/ansible/site.yml"

if [[ ! -f "${PLAYBOOK}" ]]; then
  error "Playbook não encontrado: ${PLAYBOOK}"
fi

# Exporta as variáveis do .env do geonode-cluster para o ambiente
# O geonode-cluster usa lookup('env', ...) no Ansible
CLUSTER_ENV="${REPO_DIR}/envs/.env"
if [[ -f "${CLUSTER_ENV}" ]]; then
  set -o allexport
  # shellcheck disable=SC1090
  source <(grep -v '^\s*#' "${CLUSTER_ENV}" | grep -v '^\s*$')
  set +o allexport
  info "Variáveis do geonode-cluster exportadas para o ambiente Ansible."
fi

info "ansible-playbook ${PLAYBOOK}"
ansible-playbook \
  -i "${INVENTORY}" \
  "${PLAYBOOK}" \
  -v

success "Deploy concluído com sucesso!"
echo ""

# Determina esquema e hostname a partir das variáveis carregadas
SCHEME=$([ "${HTTPS:-0}" = "1" ] && echo "https" || echo "http")
FLOATING_IP="${FLOATING_IP_VIP:-}"
VIP_IP="${IP_HAPROXY_VIP:-}"
PUBLIC_HOST="${GEONODE_PUBLIC_HOSTNAME:-${FLOATING_IP:-${VIP_IP}}}"

echo -e "${BOLD}  GeoNode disponível em:${RESET}"
if [[ -n "${FLOATING_IP}" ]]; then
  echo "    ${SCHEME}://${PUBLIC_HOST}  (Floating IP público)"
fi
echo "    ${SCHEME}://${VIP_IP}  (VIP interno — acessível via WireGuard)"
if [[ "${HTTPS:-0}" = "1" ]]; then
  echo ""
  if [[ "${LETS_ENCRYPT:-0}" = "1" ]]; then
    echo -e "    ${GREEN}✔ TLS ativo — certificado Let's Encrypt (${LETSENCRYPT_EMAIL:-})${RESET}"
  else
    echo -e "    ${YELLOW}⚠ TLS ativo — certificado autoassinado${RESET}"
  fi
fi
echo ""
echo -e "${BOLD}  Credenciais:${RESET}"
echo "    GeoNode admin: ${GEONODE_ADMIN_USER:-admin} / ${GEONODE_ADMIN_PASSWORD}"
echo "    GeoServer    : ${GEOSERVER_ADMIN_USER:-admin} / ${GEOSERVER_ADMIN_PASSWORD}"
