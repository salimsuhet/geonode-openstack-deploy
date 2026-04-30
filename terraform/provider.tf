############################################################
# provider.tf — autenticação OpenStack via variáveis de ambiente
#
# As credenciais são lidas das variáveis OS_* injetadas pelo
# bootstrap.sh a partir do envs/.env do projeto.
############################################################

terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = ">= 1.42.0"
    }
  }
}

provider "openstack" {
  auth_url    = var.os_auth_url
  tenant_name = var.os_project_name
  user_name   = var.os_username
  password    = var.os_password
  region      = var.os_region_name
  insecure    = true
}
