############################################################
# variables.tf — declaração de todas as variáveis
# Valores padrão correspondem ao .env.sample.
############################################################

# ── OpenStack ──────────────────────────────────────────────

variable "os_auth_url" {
  description = "URL do Keystone (OS_AUTH_URL)"
  type        = string
}

variable "os_project_name" {
  description = "Nome do projeto/tenant (OS_PROJECT_NAME)"
  type        = string
}

variable "os_username" {
  description = "Usuário OpenStack (OS_USERNAME)"
  type        = string
}

variable "os_password" {
  description = "Senha OpenStack (OS_PASSWORD)"
  type        = string
  sensitive   = true
}

variable "os_region_name" {
  description = "Região OpenStack"
  type        = string
  default     = "RegionOne"
}

variable "os_private_network_name" {
  description = "Nome da rede privada do tenant"
  type        = string
}

variable "os_private_subnet_name" {
  description = "Nome da subnet privada do tenant"
  type        = string
}

variable "os_provider_network" {
  description = "Nome da provider network (para Floating IPs)"
  type        = string
  default     = "provider-network"
}

variable "os_image_name" {
  description = "Nome da imagem base (Ubuntu 24.04)"
  type        = string
  default     = "ubuntu-24.04"
}

# ── Flavors ────────────────────────────────────────────────

variable "flavor_db" {
  description = "Flavor da instância de banco de dados"
  type        = string
  default     = "m1.large"
}

variable "flavor_geonode" {
  description = "Flavor da instância GeoNode"
  type        = string
  default     = "m1.large"
}

variable "flavor_geoserver_write" {
  description = "Flavor do GeoServer master (write)"
  type        = string
  default     = "m1.large"
}

variable "flavor_geoserver_read" {
  description = "Flavor dos workers GeoServer (read)"
  type        = string
  default     = "m1.medium"
}

variable "flavor_haproxy" {
  description = "Flavor das instâncias HAProxy"
  type        = string
  default     = "m1.small"
}

# ── IPs fixos ──────────────────────────────────────────────

variable "ip_db" {
  description = "IP fixo — banco de dados"
  type        = string
  default     = "192.168.1.100"
}

variable "ip_geonode" {
  description = "IP fixo — GeoNode"
  type        = string
  default     = "192.168.1.101"
}

variable "ip_geoserver_write" {
  description = "IP fixo — GeoServer write (master)"
  type        = string
  default     = "192.168.1.102"
}

variable "ip_geoserver_read_1" {
  description = "IP fixo — GeoServer read worker 1"
  type        = string
  default     = "192.168.1.103"
}

variable "ip_geoserver_read_2" {
  description = "IP fixo — GeoServer read worker 2"
  type        = string
  default     = "192.168.1.104"
}

variable "ip_haproxy_1" {
  description = "IP fixo — HAProxy 1 (MASTER)"
  type        = string
  default     = "192.168.1.105"
}

variable "ip_haproxy_2" {
  description = "IP fixo — HAProxy 2 (BACKUP)"
  type        = string
  default     = "192.168.1.106"
}

variable "ip_haproxy_vip" {
  description = "IP virtual do Keepalived (VRRP) — não atribuído diretamente"
  type        = string
  default     = "192.168.1.107"
}

variable "create_floating_ip_for_vip" {
  description = "Se true, aloca Floating IP e associa ao haproxy-1 para acesso externo"
  type        = bool
  default     = true
}

# ── SSH ────────────────────────────────────────────────────

variable "ssh_public_key_path" {
  description = "Caminho para a chave pública SSH injetada nas instâncias"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
