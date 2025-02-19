terraform {
  required_providers {
    shell = {
      source = "scottwinkler/shell"
      version = "1.7.10"
    }
  }
}

provider "shell" {
  enable_parallelism = true
}

resource "shell_script" "ansiblevms" {
  # count = (var.is_runtime ? var.worker_count + 3 : 1) + local.maprcount
  lifecycle_commands {
    create = file("./ansible-create.sh")
    delete = file("./ansible-delete.sh")
  }

  interpreter = ["/bin/bash", "-c"]
}

output "controller_private_ips" {
  value = jsondecode(shell_script.ansiblevms.output.controller)["hosts"]
}
output "controller_private_dns" {
  value = jsondecode(shell_script.ansiblevms.output.controller)["hosts"]
}
output "gateway_private_ips" {
  value = jsondecode(shell_script.ansiblevms.output.gateway)["hosts"]
}
output "gateway_public_ips" {
  value = jsondecode(shell_script.ansiblevms.output.gateway)["hosts"]
}
output "gateway_private_dns" {
  value = jsondecode(shell_script.ansiblevms.output.gateway)["hosts"]
}
output "gateway_public_dns" {
  ### VERIFY THIS
  value = [ for k, v in jsondecode(shell_script.ansiblevms.output._meta)["hostvars"] : v["gw_host"] ][0]
}
output "worker_count" {
  value = jsondecode(shell_script.ansiblevms.output.k8s)["hosts"]
}
output "workers_private_ip" {
  ### VERIFY THIS
  value = length(jsondecode(shell_script.ansiblevms.output.k8s)["hosts"])
}
output "gworker_count" {
  value = 0
}
output "gworkers_private_ip" {
  value = [ ]
}
# output "mapr_count" {
#   value = var.mapr_count
# }
# output "mapr_private_ips" {
#   value = jsondecode(shell_script.ansiblevms.output.mapr)["hosts"]
# }
output "ad_server_private_ip" {
  ### VERIFY THIS ["bound_dns"]
  value = [ for k, v in jsondecode(shell_script.ansiblevms.output._meta)["hostvars"] : v["bound_dns"] ][0]
}
