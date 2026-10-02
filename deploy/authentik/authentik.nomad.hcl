# Authentik — servidor de autenticación centralizado (OIDC/SAML/LDAP)
#
# Despliegue: Nomad -> Docker, con Traefik como reverse proxy y Consul
# para service discovery.
#
# Analogía: Authentik es a Keycloak lo que Gitea es a GitLab.
#
# Variables que debes ajustar antes de lanzar el job:
#   - AUTHENTIK_SECRET_KEY  (obligatoria, secreta)
#   - AUTHENTIK_POSTGRESQL__PASSWORD (obligatoria, secreta)
#   - Host de PostgreSQL existente
#
# Uso:
#   nomad job run deploy/authentik/authentik.nomad.hcl

job "authentik" {
  datacenters = ["dc1"]
  type        = "service"

  update {
    max_parallel      = 1
    health_check      = "checks"
    min_healthy_time  = "30s"
    healthy_deadline  = "5m"
    progress_deadline = "10m"
    auto_revert       = true
  }

  group "server" {
    count = 1

    shutdown_delay = "15s"

    network {
      port "http" {
        to = 9000
      }
    }

    # Traefik descubre el servicio vía Consul y enruta auth.app.brisecom.net
    service {
      name     = "authentik-server"
      provider = "consul"
      port     = "http"

      tags = [
        "traefik.enable=true",
        "traefik.http.routers.authentik.rule=Host(`auth.app.brisecom.net`)",
        "traefik.http.routers.authentik.entrypoints=websecure",
        "traefik.http.routers.authentik.tls=true",
        "traefik.http.routers.authentik.tls.certresolver=letsencrypt",
        "traefik.http.services.authentik.loadbalancer.server.port=9000",
      ]

      check {
        name     = "authentik-server-health"
        type     = "http"
        path     = "/-/health/live/"
        interval = "30s"
        timeout  = "5s"
      }
    }

    task "server" {
      driver = "docker"

      config {
        image = "ghcr.io/goauthentik/server:2024.10"
        args  = ["server"]
        ports = ["http"]
      }

      # Valores NO secretos (se pueden versionar)
      env {
        AUTHENTIK_REDIS__HOST      = "redis.service.consul"
        AUTHENTIK_POSTGRESQL__HOST = "postgres.service.consul"
        AUTHENTIK_POSTGRESQL__USER = "authentik"
        AUTHENTIK_POSTGRESQL__NAME = "authentik"
        AUTHENTIK_ERROR_REPORTING__ENABLED = "false"
      }

      # Secretos: se inyectan desde Nomad Variables o plantilla Vault.
      # Ejemplo con Nomad Variables (nomad var put nomad/jobs/authentik ...):
      #
      #   template {
      #     data        = <<EOH
      # AUTHENTIK_SECRET_KEY={{ with nomadVar "nomad/jobs/authentik" }}{{ .secret_key }}{{ end }}
      # AUTHENTIK_POSTGRESQL__PASSWORD={{ with nomadVar "nomad/jobs/authentik" }}{{ .postgres_password }}{{ end }}
      # EOH
      #     destination = "secrets/authentik.env"
      #     env         = true
      #   }

      resources {
        cpu    = 500
        memory = 1024
      }

      restart {
        attempts = 3
        interval = "10m"
        delay    = "30s"
        mode     = "fail"
      }
    }
  }

  group "worker" {
    count = 1

    task "worker" {
      driver = "docker"

      config {
        image = "ghcr.io/goauthentik/server:2024.10"
        args  = ["worker"]
      }

      env {
        AUTHENTIK_REDIS__HOST      = "redis.service.consul"
        AUTHENTIK_POSTGRESQL__HOST = "postgres.service.consul"
        AUTHENTIK_POSTGRESQL__USER = "authentik"
        AUTHENTIK_POSTGRESQL__NAME = "authentik"
        AUTHENTIK_ERROR_REPORTING__ENABLED = "false"
      }

      resources {
        cpu    = 500
        memory = 1024
      }

      restart {
        attempts = 3
        interval = "10m"
        delay    = "30s"
        mode     = "fail"
      }
    }
  }
}
