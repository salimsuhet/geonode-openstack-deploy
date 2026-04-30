# =============================================================================
# Makefile — geonode-openstack-deploy
# =============================================================================

SHELL        := /bin/bash
.DEFAULT_GOAL := help

ENV_FILE     ?= envs/.env
TF_DIR       := terraform
REPO_DIR     := geonode-cluster
SCRIPTS      := scripts

# Carrega variáveis do .env se existir
ifneq (,$(wildcard $(ENV_FILE)))
  include $(ENV_FILE)
  export
endif

GEONODE_BRANCH ?= main

# =============================================================================
.PHONY: help
help: ## Exibe esta ajuda
	@awk 'BEGIN {FS = ":.*##"; printf "\n\033[1mgeonode-openstack-deploy — Comandos\033[0m\n\n"} \
	  /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-28s\033[0m %s\n", $$1, $$2 }' \
	  $(MAKEFILE_LIST)
	@echo ""

# =============================================================================
# Setup
# =============================================================================

.PHONY: env
env: ## Cria envs/.env a partir do .env.sample (se não existir)
	@[ -f $(ENV_FILE) ] \
	  && echo "$(ENV_FILE) já existe." \
	  || (cp envs/.env.sample $(ENV_FILE) && echo "✔ $(ENV_FILE) criado. Edite antes de continuar.")

.PHONY: deps
deps: ## Instala dependências (Ansible collections, python3)
	@command -v ansible-galaxy &>/dev/null || (echo "✗ ansible não encontrado"; exit 1)
	@[ -f $(REPO_DIR)/ansible/requirements.yml ] \
	  && ansible-galaxy collection install -r $(REPO_DIR)/ansible/requirements.yml \
	  || echo "requirements.yml não encontrado (clone o repo primeiro com make clone)"

# =============================================================================
# Pipeline principal
# =============================================================================

.PHONY: deploy
deploy: env ## Pipeline completo: Terraform + clone + .env + Ansible
	bash $(SCRIPTS)/bootstrap.sh

.PHONY: deploy-auto
deploy-auto: env ## Pipeline completo sem confirmação interativa
	bash $(SCRIPTS)/bootstrap.sh --auto-approve

.PHONY: deploy-check
deploy-check: ## Dry-run do Ansible (--check --diff)
	@$(MAKE) generate-env generate-inventory
	@source $(ENV_FILE) && \
	  export $$(grep -v '^#' $(REPO_DIR)/envs/.env | xargs) && \
	  ansible-playbook \
	    -i $(REPO_DIR)/ansible/inventories/production/hosts.yml \
	    $(REPO_DIR)/ansible/site.yml \
	    --check --diff

# =============================================================================
# Terraform
# =============================================================================

.PHONY: tf-only
tf-only: env ## Apenas Terraform (sem clone nem Ansible)
	bash $(SCRIPTS)/bootstrap.sh --tf-only

.PHONY: tf-init
tf-init: ## terraform init
	cd $(TF_DIR) && terraform init -upgrade

.PHONY: tf-plan
tf-plan: generate-tfvars ## terraform plan
	cd $(TF_DIR) && terraform plan -var-file=terraform.tfvars

.PHONY: tf-apply
tf-apply: generate-tfvars ## terraform apply (pede confirmação)
	cd $(TF_DIR) && terraform plan -var-file=terraform.tfvars -out=out.plan
	cd $(TF_DIR) && terraform apply out.plan

.PHONY: tf-destroy
tf-destroy: generate-tfvars ## Destroi toda a infraestrutura (irreversível!)
	cd $(TF_DIR) && terraform plan -destroy -var-file=terraform.tfvars -out=out-destroy.plan
	cd $(TF_DIR) && terraform apply out-destroy.plan

.PHONY: tf-output
tf-output: ## Exibe outputs do Terraform
	cd $(TF_DIR) && terraform output

# =============================================================================
# Geração de arquivos
# =============================================================================

.PHONY: generate-tfvars
generate-tfvars: ## Gera terraform/terraform.tfvars a partir do .env
	bash $(SCRIPTS)/generate-tfvars.sh

.PHONY: generate-env
generate-env: ## Gera geonode-cluster/envs/.env a partir do .env + terraform outputs
	bash $(SCRIPTS)/generate-env.sh

.PHONY: generate-inventory
generate-inventory: ## Gera inventário Ansible de produção
	bash $(SCRIPTS)/generate-inventory.sh

# =============================================================================
# Repositório geonode-cluster
# =============================================================================

.PHONY: clone
clone: ## Clona geonode-cluster no branch definido em GEONODE_BRANCH
	@BRANCH=$(GEONODE_BRANCH) && \
	  if [ -d $(REPO_DIR)/.git ]; then \
	    echo "Repositório existe — atualizando para branch $$BRANCH..."; \
	    cd $(REPO_DIR) && git fetch origin && git checkout $$BRANCH && git pull origin $$BRANCH; \
	  else \
	    git clone --branch $$BRANCH https://github.com/salimsuhet/geonode-cluster.git $(REPO_DIR); \
	  fi
	@echo "✔ $(REPO_DIR) @ branch $(GEONODE_BRANCH)"

.PHONY: switch-branch
switch-branch: ## Muda branch do geonode-cluster (uso: make switch-branch GEONODE_BRANCH=nome)
	@[ -d $(REPO_DIR)/.git ] || (echo "✗ Clone o repositório primeiro: make clone"; exit 1)
	@echo "→ Trocando para branch $(GEONODE_BRANCH)..."
	cd $(REPO_DIR) && git fetch origin && git checkout $(GEONODE_BRANCH) && git pull origin $(GEONODE_BRANCH)
	@echo "✔ Branch trocado para $(GEONODE_BRANCH). Execute make generate-env generate-inventory para regenerar."

# =============================================================================
# Deploy Ansible (sem Terraform)
# =============================================================================

.PHONY: ansible-only
ansible-only: generate-env generate-inventory ## Apenas Ansible (Terraform já aplicado)
	bash $(SCRIPTS)/bootstrap.sh --ansible-only

.PHONY: ansible-tag
ansible-tag: ## Executa apenas uma tag Ansible (uso: make ansible-tag TAG=geoserver)
	@[ -n "$(TAG)" ] || (echo "✗ Uso: make ansible-tag TAG=<nome>"; exit 1)
	@source $(ENV_FILE) && \
	  export $$(grep -v '^#' $(REPO_DIR)/envs/.env | xargs) && \
	  ansible-playbook \
	    -i $(REPO_DIR)/ansible/inventories/production/hosts.yml \
	    $(REPO_DIR)/ansible/site.yml \
	    --tags $(TAG)

.PHONY: ping
ping: ## Testa conectividade Ansible com todos os hosts
	@[ -d $(REPO_DIR)/ansible ] || (echo "✗ Clone o repositório primeiro: make clone"; exit 1)
	ansible -i $(REPO_DIR)/ansible/inventories/production/hosts.yml all -m ping

# =============================================================================
# Utilitários
# =============================================================================

.PHONY: show-env
show-env: ## Exibe o .env do geonode-cluster que será entregue
	@[ -f $(REPO_DIR)/envs/.env ] && cat $(REPO_DIR)/envs/.env || echo "Não gerado ainda. Execute: make generate-env"

.PHONY: show-inventory
show-inventory: ## Exibe o inventário Ansible de produção
	@[ -f $(REPO_DIR)/ansible/inventories/production/hosts.yml ] \
	  && cat $(REPO_DIR)/ansible/inventories/production/hosts.yml \
	  || echo "Não gerado ainda. Execute: make generate-inventory"

.PHONY: clean
clean: ## Remove arquivos gerados (terraform.tfvars, out.plan, geonode-cluster/)
	@echo "Isso removerá terraform/terraform.tfvars, terraform/out*.plan e o diretório geonode-cluster/."
	@read -p "Confirma? [s/N] " C && [[ "$$C" =~ ^[sS]$$ ]] || exit 0
	rm -f $(TF_DIR)/terraform.tfvars $(TF_DIR)/out*.plan
	rm -rf $(REPO_DIR)
	find . -name "*.retry" -delete 2>/dev/null || true
	@echo "✔ Limpeza concluída."
