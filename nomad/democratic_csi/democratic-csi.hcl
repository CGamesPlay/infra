job "democratic-csi" {
  datacenters = ["nbg1"]
  type        = "system"
  priority    = 90

  group "controller" {
    volume "host-volume" {
      type   = "host"
      source = "csi_storage_master"
    }

    network {
      port "grpc" {}
    }

    task "controller" {
      driver = "docker"
      config {
        image = "democraticcsi/democratic-csi:v1.8.3"
        ports = ["grpc"]
        args = [
          "--csi-version=1.2.0",
          "--csi-name=org.democratic-csi.nfs",
          "--driver-config-file=${NOMAD_TASK_DIR}/driver-config-file.yaml",
          "--log-level=debug",
          "--csi-mode=controller",
          "--csi-mode=node",
          "--server-socket=/csi-data/csi.sock",
          "--server-address=0.0.0.0",
          "--server-port=${NOMAD_PORT_grpc}",
        ]
        privileged = true
      }

      csi_plugin {
        id        = "democratic-csi"
        type      = "monolith"
        mount_dir = "/csi-data"
      }

      volume_mount {
        volume      = "host-volume"
        destination = "/opt/csi"
      }

      template {
        destination = "${NOMAD_TASK_DIR}/driver-config-file.yaml"
        data        = <<-EOF
        driver: local-hostpath
        instance_id:
        local-hostpath:
          # generally shareBasePath and controllerBasePath should be the same for this
          # driver, this path should be mounted into the csi-driver container
          shareBasePath:      "/opt/csi"
          controllerBasePath: "/opt/csi"
          dirPermissionsMode: "0777"
          dirPermissionsUser: 0
          dirPermissionsGroup: 0
        EOF
      }

      resources {
        cpu        = 30
        memory     = 64
        memory_max = 256
      }
    }
  }
}
