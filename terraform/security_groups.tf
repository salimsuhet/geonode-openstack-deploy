############################################################
# security_groups.tf — grupos de segurança por camada
#
# Modelo de menor privilégio: cada SG abre apenas as portas
# necessárias para a função da instância.
############################################################

# ── Default do projeto (data source) ──────────────────────
# Necessário para DHCP e comunicação intra-projeto.

data "openstack_networking_secgroup_v2" "default" {
  name      = "default"
  tenant_id = data.openstack_identity_project_v3.current_project.id
}

data "openstack_identity_project_v3" "current_project" {
  name = var.os_project_name
}

# ── Banco de dados ─────────────────────────────────────────

resource "openstack_networking_secgroup_v2" "db" {
  name        = "geonode-db"
  description = "PostgreSQL acessível apenas pelos nós do cluster"
}

# PostgreSQL — apenas de dentro da subnet privada
resource "openstack_networking_secgroup_rule_v2" "db_postgres" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5432
  port_range_max    = 5432
  remote_ip_prefix  = data.openstack_networking_subnet_v2.private_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.db.id
}

# SSH — apenas de dentro da subnet (Ansible)
resource "openstack_networking_secgroup_rule_v2" "db_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = data.openstack_networking_subnet_v2.private_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.db.id
}

# ── GeoNode app ────────────────────────────────────────────

resource "openstack_networking_secgroup_v2" "geonode" {
  name        = "geonode-app"
  description = "GeoNode Django/Celery"
}

resource "openstack_networking_secgroup_rule_v2" "geonode_http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8000
  port_range_max    = 8000
  remote_ip_prefix  = data.openstack_networking_subnet_v2.private_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.geonode.id
}

resource "openstack_networking_secgroup_rule_v2" "geonode_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = data.openstack_networking_subnet_v2.private_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.geonode.id
}

# ── GeoServer ──────────────────────────────────────────────

resource "openstack_networking_secgroup_v2" "geoserver" {
  name        = "geonode-geoserver"
  description = "GeoServer HTTP + JMS ActiveMQ + NFS"
}

# GeoServer HTTP
resource "openstack_networking_secgroup_rule_v2" "geoserver_http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8080
  port_range_max    = 8080
  remote_ip_prefix  = data.openstack_networking_subnet_v2.private_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.geoserver.id
}

# JMS/ActiveMQ (broker de sincronização do cluster)
resource "openstack_networking_secgroup_rule_v2" "geoserver_jms" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 61661
  port_range_max    = 61661
  remote_ip_prefix  = data.openstack_networking_subnet_v2.private_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.geoserver.id
}

# NFS (TCP + UDP 2049) — montagem do datadir compartilhado
resource "openstack_networking_secgroup_rule_v2" "geoserver_nfs_tcp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 2049
  port_range_max    = 2049
  remote_ip_prefix  = data.openstack_networking_subnet_v2.private_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.geoserver.id
}

resource "openstack_networking_secgroup_rule_v2" "geoserver_nfs_udp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 2049
  port_range_max    = 2049
  remote_ip_prefix  = data.openstack_networking_subnet_v2.private_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.geoserver.id
}

resource "openstack_networking_secgroup_rule_v2" "geoserver_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = data.openstack_networking_subnet_v2.private_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.geoserver.id
}

# ── HAProxy / Keepalived ───────────────────────────────────

resource "openstack_networking_secgroup_v2" "haproxy" {
  name        = "geonode-haproxy"
  description = "HAProxy HTTP/HTTPS + stats + VRRP Keepalived"
}

# HTTP público
resource "openstack_networking_secgroup_rule_v2" "haproxy_http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.haproxy.id
}

# HTTPS público
resource "openstack_networking_secgroup_rule_v2" "haproxy_https" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.haproxy.id
}

# Stats page (acesso restrito à subnet)
resource "openstack_networking_secgroup_rule_v2" "haproxy_stats" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 8404
  port_range_max    = 8404
  remote_ip_prefix  = data.openstack_networking_subnet_v2.private_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.haproxy.id
}

# VRRP (protocolo 112) entre os dois HAProxy
resource "openstack_networking_secgroup_rule_v2" "haproxy_vrrp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "112"  # VRRP
  remote_ip_prefix  = data.openstack_networking_subnet_v2.private_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.haproxy.id
}

resource "openstack_networking_secgroup_rule_v2" "haproxy_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = data.openstack_networking_subnet_v2.private_subnet.cidr
  security_group_id = openstack_networking_secgroup_v2.haproxy.id
}
