############################################################
# networking.tf — portas das instâncias e VIP do Keepalived
#
# Não cria redes/roteadores: reutiliza a rede privada e a
# provider network já provisionadas pelo nerdstack para o tenant.
#
# VIP Keepalived: implementado via allowed_address_pairs nas
# portas dos dois HAProxy, permitindo que o VRRP migre o IP
# virtual entre as instâncias sem intervenção no Neutron.
############################################################

# ── Data sources: rede e subnet existentes ─────────────────

data "openstack_networking_network_v2" "private_net" {
  name = var.os_private_network_name
}

data "openstack_networking_subnet_v2" "private_subnet" {
  name = var.os_private_subnet_name
}

# ── Security groups ────────────────────────────────────────
# (definidos em security_groups.tf — importados aqui apenas para
#  referência nas portas via depends_on)

# ── Portas com IP fixo ─────────────────────────────────────

resource "openstack_networking_port_v2" "db" {
  name       = "geonode-db-port"
  network_id = data.openstack_networking_network_v2.private_net.id

  fixed_ip {
    subnet_id  = data.openstack_networking_subnet_v2.private_subnet.id
    ip_address = var.ip_db
  }

  security_group_ids = [
    openstack_networking_secgroup_v2.db.id,
    data.openstack_networking_secgroup_v2.default.id,
  ]
}

resource "openstack_networking_port_v2" "geonode" {
  name       = "geonode-app-port"
  network_id = data.openstack_networking_network_v2.private_net.id

  fixed_ip {
    subnet_id  = data.openstack_networking_subnet_v2.private_subnet.id
    ip_address = var.ip_geonode
  }

  security_group_ids = [
    openstack_networking_secgroup_v2.geonode.id,
    data.openstack_networking_secgroup_v2.default.id,
  ]
}

resource "openstack_networking_port_v2" "geoserver_write" {
  name       = "geonode-geoserver-write-port"
  network_id = data.openstack_networking_network_v2.private_net.id

  fixed_ip {
    subnet_id  = data.openstack_networking_subnet_v2.private_subnet.id
    ip_address = var.ip_geoserver_write
  }

  security_group_ids = [
    openstack_networking_secgroup_v2.geoserver.id,
    data.openstack_networking_secgroup_v2.default.id,
  ]
}

resource "openstack_networking_port_v2" "geoserver_read_1" {
  name       = "geonode-geoserver-read-1-port"
  network_id = data.openstack_networking_network_v2.private_net.id

  fixed_ip {
    subnet_id  = data.openstack_networking_subnet_v2.private_subnet.id
    ip_address = var.ip_geoserver_read_1
  }

  security_group_ids = [
    openstack_networking_secgroup_v2.geoserver.id,
    data.openstack_networking_secgroup_v2.default.id,
  ]
}

resource "openstack_networking_port_v2" "geoserver_read_2" {
  name       = "geonode-geoserver-read-2-port"
  network_id = data.openstack_networking_network_v2.private_net.id

  fixed_ip {
    subnet_id  = data.openstack_networking_subnet_v2.private_subnet.id
    ip_address = var.ip_geoserver_read_2
  }

  security_group_ids = [
    openstack_networking_secgroup_v2.geoserver.id,
    data.openstack_networking_secgroup_v2.default.id,
  ]
}

# HAProxy 1 — com allowed_address_pairs para o VIP Keepalived
resource "openstack_networking_port_v2" "haproxy_1" {
  name       = "geonode-haproxy-1-port"
  network_id = data.openstack_networking_network_v2.private_net.id

  fixed_ip {
    subnet_id  = data.openstack_networking_subnet_v2.private_subnet.id
    ip_address = var.ip_haproxy_1
  }

  # Permite que o VIP Keepalived seja anunciado via GARP nesta porta
  allowed_address_pairs {
    ip_address = var.ip_haproxy_vip
  }

  security_group_ids = [
    openstack_networking_secgroup_v2.haproxy.id,
    data.openstack_networking_secgroup_v2.default.id,
  ]
}

# HAProxy 2 — idem
resource "openstack_networking_port_v2" "haproxy_2" {
  name       = "geonode-haproxy-2-port"
  network_id = data.openstack_networking_network_v2.private_net.id

  fixed_ip {
    subnet_id  = data.openstack_networking_subnet_v2.private_subnet.id
    ip_address = var.ip_haproxy_2
  }

  allowed_address_pairs {
    ip_address = var.ip_haproxy_vip
  }

  security_group_ids = [
    openstack_networking_secgroup_v2.haproxy.id,
    data.openstack_networking_secgroup_v2.default.id,
  ]
}

# ── Floating IP para o VIP (acesso externo) ────────────────
#
# Associado à porta do haproxy-1 (MASTER inicial).
# Quando o Keepalived faz failover para o haproxy-2, o tráfego
# continua chegando pelo FIP ao IP privado do haproxy corrente
# via a lógica do allowed_address_pairs.
#
# Nota: para um failover totalmente transparente em OpenStack,
# o ideal é usar um port separado para o VIP e reassociá-lo via
# API do Neutron durante o failover (requer script de notificação
# no Keepalived). A abordagem aqui é suficiente para ambientes
# onde o FIP aponta para o MASTER e o failover é aceito com breve
# indisponibilidade do FIP. Documente conforme sua necessidade.

resource "openstack_networking_floatingip_v2" "vip_fip" {
  count = var.create_floating_ip_for_vip ? 1 : 0
  pool  = var.os_provider_network
}

resource "openstack_networking_floatingip_associate_v2" "vip_fip_assoc" {
  count       = var.create_floating_ip_for_vip ? 1 : 0
  floating_ip = openstack_networking_floatingip_v2.vip_fip[0].address
  port_id     = openstack_networking_port_v2.haproxy_1.id
}
