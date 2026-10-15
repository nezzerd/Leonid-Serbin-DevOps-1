variable "vm_ip" {
  description = "Address used in the HTTP output for the supplied VM."
  type        = string
  default     = "111.88.162.96"
}

variable "docker_host" {
  description = "Docker daemon endpoint. SSH keeps the Docker API closed to the Internet."
  type        = string
  default     = "ssh://student@111.88.162.96:22"
}

variable "docker_ssh_opts" {
  description = "Extra OpenSSH options passed by the Docker provider."
  type        = list(string)
  default     = ["-o", "StrictHostKeyChecking=accept-new"]
}

variable "nginx_image" {
  description = "Pinned nginx image used by the Terraform-managed container."
  type        = string
  default     = "nginx:1.27-alpine"
}

variable "nginx_container_name" {
  description = "Docker container name for the Terraform-managed nginx."
  type        = string
  default     = "devops-tf-nginx"
}

variable "nginx_network_name" {
  description = "Dedicated network for the Terraform-managed nginx only."
  type        = string
  default     = "devops_terraform_nginx"
}

variable "nginx_volume_name" {
  description = "Named volume mounted at /usr/share/nginx/html."
  type        = string
  default     = "devops_nginx_html"
}

variable "nginx_host_port" {
  description = "Non-standard host port published to container port 80."
  type        = number
  default     = 8088

  validation {
    condition     = var.nginx_host_port >= 1024 && var.nginx_host_port <= 65535
    error_message = "nginx_host_port must be between 1024 and 65535."
  }
}
