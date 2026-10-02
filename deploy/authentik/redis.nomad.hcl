# Redis para Authentik (cache y broker de tareas).
#
# Si ya tienes un Redis en Consul como `redis.service.consul`, NO lances este
# job y ajusta AUTHENTIK_REDIS__HOST en authentik.nomad.hcl.
#
# Uso:
#   nomad job run deploy/authentik/redis.nomad.hcl

job "authentik-redis" {
  datacenters = ["dc1"]
  type        = "service"

  group "redis" {
    count = 1

    shutdown_delay = "15s"

    network {
      port "redis" {
        to = 6379
      }
    }

    service {
      name     = "redis"
      provider = "consul"
      port     = "redis"

      check {
        name     = "redis-tcp"
        type     = "tcp"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "redis" {
      driver = "docker"

      config {
        image = "redis:7-alpine"
        args  = ["redis-server", "--appendonly", "yes"]
        ports = ["redis"]

        volumes = [
          "local/redis-data:/data",
        ]
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
