############################################################
# outputs.tf — exporta IPs e informações usadas pelos scripts
############################################################

output "ip_db" {
  value       = var.ip_db
  description = "IP fixo — banco de dados"
}

output "ip_geonode" {
  value       = var.ip_geonode
  description = "IP fixo — GeoNode app"
}

output "ip_geoserver_write" {
  value       = var.ip_geoserver_write
  description = "IP fixo — GeoServer master (write)"
}

output "ip_geoserver_read_1" {
  value       = var.ip_geoserver_read_1
  description = "IP fixo — GeoServer worker 1 (read)"
}

output "ip_geoserver_read_2" {
  value       = var.ip_geoserver_read_2
  description = "IP fixo — GeoServer worker 2 (read)"
}

output "ip_haproxy_1" {
  value       = var.ip_haproxy_1
  description = "IP fixo — HAProxy 1 (MASTER)"
}

output "ip_haproxy_2" {
  value       = var.ip_haproxy_2
  description = "IP fixo — HAProxy 2 (BACKUP)"
}

output "ip_haproxy_vip" {
  value       = var.ip_haproxy_vip
  description = "VIP Keepalived"
}

output "floating_ip_vip" {
  value       = var.create_floating_ip_for_vip ? openstack_networking_floatingip_v2.vip_fip[0].address : null
  description = "Floating IP público do VIP (null se create_floating_ip_for_vip = false)"
}

output "instance_ids" {
  value = {
    db               = openstack_compute_instance_v2.db.id
    geonode          = openstack_compute_instance_v2.geonode.id
    geoserver_write  = openstack_compute_instance_v2.geoserver_write.id
    geoserver_read_1 = openstack_compute_instance_v2.geoserver_read_1.id
    geoserver_read_2 = openstack_compute_instance_v2.geoserver_read_2.id
    haproxy_1        = openstack_compute_instance_v2.haproxy_1.id
    haproxy_2        = openstack_compute_instance_v2.haproxy_2.id
  }
  description = "IDs das instâncias OpenStack"
}

output "ssh_keypair_name" {
  value       = openstack_compute_keypair_v2.geonode_key.name
  description = "Nome do keypair SSH injetado nas instâncias"
}
