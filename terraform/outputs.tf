output "nginx_url" {
  description = "URL of the Terraform-managed nginx."
  value       = "http://${var.vm_ip}:${var.nginx_host_port}/"
}

output "nginx_network" {
  description = "Dedicated Docker network created by Terraform."
  value       = docker_network.nginx.name
}

output "nginx_volume" {
  description = "Named Docker volume mounted into nginx."
  value       = docker_volume.nginx_html.name
}
