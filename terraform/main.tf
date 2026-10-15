provider "docker" {
  host     = var.docker_host
  ssh_opts = var.docker_ssh_opts
}

resource "docker_network" "nginx" {
  name   = var.nginx_network_name
  driver = "bridge"
}

resource "docker_volume" "nginx_html" {
  name = var.nginx_volume_name
}

resource "docker_image" "nginx" {
  name         = var.nginx_image
  keep_locally = true
}

resource "docker_container" "nginx" {
  name     = var.nginx_container_name
  image    = docker_image.nginx.image_id
  restart  = "unless-stopped"
  must_run = true

  networks_advanced {
    name = docker_network.nginx.name
  }

  ports {
    internal = 80
    external = var.nginx_host_port
    protocol = "tcp"
  }

  volumes {
    volume_name    = docker_volume.nginx_html.name
    container_path = "/usr/share/nginx/html"
  }

  upload {
    file        = "/usr/share/nginx/html/index.html"
    source      = "${path.module}/nginx/index.html"
    source_hash = filesha256("${path.module}/nginx/index.html")
  }

  healthcheck {
    test     = ["CMD-SHELL", "wget -q --spider http://127.0.0.1/ || exit 1"]
    interval = "30s"
    timeout  = "5s"
    retries  = 3
  }
}
