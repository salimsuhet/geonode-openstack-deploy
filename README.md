# geonode-openstack-deploy

Projeto Terraform + Ansible para provisionar e implantar o [geonode-cluster](https://github.com/salimsuhet/geonode-cluster) em uma infraestrutura OpenStack gerenciada pelo **nerdstack-tenants-provisioner**.

---

## Visão Geral

```
geonode-openstack-deploy/
├── envs/
│   └── .env.sample          ← fonte única de configuração
├── terraform/
│   ├── provider.tf          ← autenticação OpenStack (tenant)
│   ├── variables.tf
│   ├── networking.tf        ← portas fixas + VIP Keepalived (allowed_address_pairs)
│   ├── instances.tf         ← 7 VMs do cluster
│   ├── security_groups.tf   ← SGs por camada (db / geonode / geoserver / haproxy)
│   ├── outputs.tf
│   └── terraform.tfvars.sample
├── scripts/
│   ├── bootstrap.sh         ← pipeline completo
│   ├── generate-tfvars.sh   ← .env → terraform.tfvars
│   ├── generate-env.sh      ← .env + tf outputs → geonode-cluster/envs/.env
│   └── generate-inventory.sh← tf outputs → hosts.yml de produção
├── Makefile
└── README.md
```

O `bootstrap.sh` orquestra tudo em uma única execução:

```
.env  ──►  terraform.tfvars  ──►  terraform apply  ──►  7 VMs OpenStack
                                        │
                                        ▼
                             tf outputs + .env  ──►  geonode-cluster/envs/.env
                                                ──►  inventories/production/hosts.yml
                                        │
                                        ▼
                             git clone geonode-cluster@${GEONODE_BRANCH}
                                        │
                                        ▼
                             ansible-playbook site.yml
```

---

## Pré-requisitos

| Ferramenta    | Versão mínima | Observação                          |
|---------------|---------------|-------------------------------------|
| Terraform     | 1.3           | `terraform -v`                      |
| Ansible       | 2.15          | `ansible --version`                 |
| python3       | 3.8           | Para processar `terraform output`   |
| git           | —             | Para clonar o geonode-cluster       |
| WireGuard     | —             | Para acesso SSH às VMs via VPN      |

O host controlador deve estar conectado via WireGuard ao tenant OpenStack para que o Ansible alcance as instâncias pela rede privada.

---

## Quotas necessárias no tenant

| VM                  | Flavor      | vCPU | RAM   |
|---------------------|-------------|------|-------|
| db                  | m1.large    | 4    | 8 GB  |
| geonode             | m1.large    | 4    | 8 GB  |
| geoserver-write     | m1.large    | 4    | 8 GB  |
| geoserver-read-1    | m1.medium   | 2    | 4 GB  |
| geoserver-read-2    | m1.medium   | 2    | 4 GB  |
| haproxy-1           | m1.small    | 1    | 2 GB  |
| haproxy-2           | m1.small    | 1    | 2 GB  |
| **Total**           |             | **18**| **36 GB** |

Quota mínima recomendada no tenant: 20 cores, 50 GB RAM, 10 instâncias, 2 Floating IPs.

---

## Início Rápido

### 1. Configurar

```bash
git clone <este-repositório> geonode-openstack-deploy
cd geonode-openstack-deploy

cp envs/.env.sample envs/.env
$EDITOR envs/.env   # preencha TODOS os campos obrigatórios
```

Campos obrigatórios em `envs/.env`:

```
OS_AUTH_URL, OS_PROJECT_NAME, OS_USERNAME, OS_PASSWORD
OS_PRIVATE_NETWORK_NAME, OS_PRIVATE_SUBNET_NAME
GEONODE_DB_PASSWORD, GEODATA_DB_PASSWORD, POSTGRES_PASSWORD
GEONODE_ADMIN_PASSWORD, GEOSERVER_ADMIN_PASSWORD, DJANGO_SECRET_KEY
```

### 2. Conectar ao WireGuard do tenant

Acesse o painel WG-Easy do seu tenant (URL fornecida pelo admin via `terraform output tenant_access_info`) e baixe a configuração de peer. Ative a VPN antes de continuar.

### 3. Escolher o branch

```bash
# No envs/.env:
GEONODE_BRANCH=main          # branch principal
GEONODE_BRANCH=feature/xyz   # branch de funcionalidade
GEONODE_BRANCH=v1.2.0        # tag específica
```

Ou passe diretamente na linha de comando:

```bash
GEONODE_BRANCH=staging make deploy
```

### 4. Deploy completo

```bash
make deploy
# ou, sem confirmação interativa:
make deploy-auto
```

---

## Comandos Disponíveis

```
make deploy              Pipeline completo (Terraform + Ansible)
make deploy-auto         Idem, sem prompt de confirmação
make deploy-check        Dry-run do Ansible (--check --diff)

make tf-only             Apenas Terraform
make tf-plan             terraform plan
make tf-apply            terraform apply
make tf-destroy          Destruir infraestrutura
make tf-output           Exibir outputs do Terraform

make clone               Clonar geonode-cluster no branch configurado
make switch-branch       Trocar branch (GEONODE_BRANCH=nome)

make ansible-only        Apenas Ansible (Terraform já aplicado)
make ansible-tag TAG=x   Executar tag específica do Ansible
make ping                Testar conectividade com os hosts

make generate-env        Regenerar geonode-cluster/envs/.env
make generate-inventory  Regenerar inventário Ansible
make show-env            Exibir .env que será entregue ao geonode-cluster
make show-inventory      Exibir inventário de produção

make clean               Remover arquivos gerados
```

---

## Fluxo de Atualização de Branch

Para trocar o branch do geonode-cluster sem recriar a infraestrutura:

```bash
# No envs/.env, altere:
GEONODE_BRANCH=nova-feature

# Atualiza repo, regenera .env e inventário, e re-executa Ansible:
make switch-branch GEONODE_BRANCH=nova-feature
make ansible-only
```

---

## Como o `.env` é entregue ao geonode-cluster

O `scripts/generate-env.sh` combina:

1. **IPs das instâncias** — lidos de `terraform output -json` (garantindo que o endereço real alocado seja usado)
2. **Senhas e configurações** — lidas de `envs/.env` deste projeto

O arquivo gerado é gravado em `geonode-cluster/envs/.env`. O `bootstrap.sh` exporta as variáveis desse arquivo para o ambiente antes de executar o `ansible-playbook`, de modo que o `lookup('env', ...)` do Ansible as encontre.

---

## VIP Keepalived no OpenStack

O Keepalived usa VRRP para migrar o IP virtual (`IP_HAPROXY_VIP`) entre `haproxy-1` e `haproxy-2`. No OpenStack, isso exige que o Neutron permita tráfego ARP originado do VIP. O `networking.tf` configura `allowed_address_pairs` com o VIP em ambas as portas HAProxy.

Um Floating IP (opcional) é alocado e associado ao `haproxy-1`. Em caso de failover do Keepalived, o tráfego interno já muda automaticamente via VRRP; o FIP continuará apontando para `haproxy-1`. Para failover completo do FIP, configure um script `notify` no Keepalived que use a API do OpenStack para reassociar o FIP à porta ativa.

---

## Estrutura de Rede

```
Internet
    │
    │  Floating IP (opcional)
    ▼
haproxy-1 (MASTER)  ◄─── VRRP ───►  haproxy-2 (BACKUP)
    │                  VIP: IP_HAPROXY_VIP
    │
    ├── geonode app (Django/Celery)
    │
    ├── geoserver-write (master JMS + NFS server)
    ├── geoserver-read-1 (worker + NFS client)
    └── geoserver-read-2 (worker + NFS client)
                │
                └── db (PostgreSQL + PostGIS)

[Toda comunicação na rede privada do tenant OpenStack]
[Acesso externo via WireGuard VPN ou Floating IP no VIP]
```

---

## Referências

- [geonode-cluster](https://github.com/salimsuhet/geonode-cluster)
- [nerdstack-tenants-provisioner](https://github.com/nerds-ufes/nerdstack-tenants-provisioner)
- [Terraform OpenStack Provider](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs)
- [Keepalived + OpenStack (allowed_address_pairs)](https://docs.openstack.org/neutron/latest/admin/config-allowed-address-pairs.html)
