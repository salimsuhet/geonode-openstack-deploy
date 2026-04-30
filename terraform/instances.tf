############################################################
# instances.tf — keypair e instâncias do cluster GeoNode
############################################################

# ── Keypair SSH ────────────────────────────────────────────

resource "openstack_compute_keypair_v2" "geonode_key" {
  name       = "geonode-cluster-key"
  public_key = file(pathexpand(var.ssh_public_key_path))

  lifecycle {
    ignore_changes = [public_key]
  }
}

# ── Instâncias ─────────────────────────────────────────────

resource "openstack_compute_instance_v2" "db" {
  name         = "geonode-db"
  image_name   = var.os_image_name
  flavor_name  = var.flavor_db
  key_pair     = openstack_compute_keypair_v2.geonode_key.name
  config_drive = true

  network {
    port = openstack_networking_port_v2.db.id
  }

  metadata = {
    role    = "database"
    cluster = "geonode"
  }

  depends_on = [openstack_networking_port_v2.db]
}

resource "openstack_compute_instance_v2" "geonode" {
  name         = "geonode-app"
  image_name   = var.os_image_name
  flavor_name  = var.flavor_geonode
  key_pair     = openstack_compute_keypair_v2.geonode_key.name
  config_drive = true

  network {
    port = openstack_networking_port_v2.geonode.id
  }

  metadata = {
    role    = "geonode"
    cluster = "geonode"
  }

  depends_on = [openstack_networking_port_v2.geonode]
}

resource "openstack_compute_instance_v2" "geoserver_write" {
  name         = "geonode-geoserver-write"
  image_name   = var.os_image_name
  flavor_name  = var.flavor_geoserver_write
  key_pair     = openstack_compute_keypair_v2.geonode_key.name
  config_drive = true

  network {
    port = openstack_networking_port_v2.geoserver_write.id
  }

  metadata = {
    role    = "geoserver_write"
    cluster = "geonode"
  }

  depends_on = [openstack_networking_port_v2.geoserver_write]
}

resource "openstack_compute_instance_v2" "geoserver_read_1" {
  name         = "geonode-geoserver-read-1"
  image_name   = var.os_image_name
  flavor_name  = var.flavor_geoserver_read
  key_pair     = openstack_compute_keypair_v2.geonode_key.name
  config_drive = true

  network {
    port = openstack_networking_port_v2.geoserver_read_1.id
  }

  metadata = {
    role    = "geoserver_read"
    cluster = "geonode"
  }

  depends_on = [openstack_networking_port_v2.geoserver_read_1]
}

resource "openstack_compute_instance_v2" "geoserver_read_2" {
  name         = "geonode-geoserver-read-2"
  image_name   = var.os_image_name
  flavor_name  = var.flavor_geoserver_read
  key_pair     = openstack_compute_keypair_v2.geonode_key.name
  config_drive = true

  network {
    port = openstack_networking_port_v2.geoserver_read_2.id
  }

  metadata = {
    role    = "geoserver_read"
    cluster = "geonode"
  }

  depends_on = [openstack_networking_port_v2.geoserver_read_2]
}

resource "openstack_compute_instance_v2" "haproxy_1" {
  name         = "geonode-haproxy-1"
  image_name   = var.os_image_name
  flavor_name  = var.flavor_haproxy
  key_pair     = openstack_compute_keypair_v2.geonode_key.name
  config_drive = true

  network {
    port = openstack_networking_port_v2.haproxy_1.id
  }

  metadata = {
    role        = "haproxy"
    keepalived  = "master"
    cluster     = "geonode"
  }

  depends_on = [openstack_networking_port_v2.haproxy_1]
}

resource "openstack_compute_instance_v2" "haproxy_2" {
  name         = "geonode-haproxy-2"
  image_name   = var.os_image_name
  flavor_name  = var.flavor_haproxy
  key_pair     = openstack_compute_keypair_v2.geonode_key.name
  config_drive = true

  network {
    port = openstack_networking_port_v2.haproxy_2.id
  }

  metadata = {
    role       = "haproxy"
    keepalived = "backup"
    cluster    = "geonode"
  }

  depends_on = [openstack_networking_port_v2.haproxy_2]
}
