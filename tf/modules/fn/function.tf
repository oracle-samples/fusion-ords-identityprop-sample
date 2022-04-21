#  Copyright (c) 2022 Oracle
#  Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

variable "function" {}
variable "compartment" {}
variable "functionsapp" {}
variable "application" {}
variable "registry" {}

locals {
  fnroot    = "${abspath(path.root)}/${var.function.fnpath}"
  rawfndata = yamldecode(file("${local.fnroot}/func.yaml"))
  fndata = {
    name    = local.rawfndata.name
    version = local.rawfndata.version
    memory  = local.rawfndata.memory
    timeout = try(local.rawfndata.timeout, 30)
    image   = "${var.registry}/${local.rawfndata.name}:${local.rawfndata.version}"
  }
}

data "external" "git_data" {
  working_dir = local.fnroot
  program = ["bash", "-c", <<EOC
  echo "{\"b\":\"$(git rev-parse --abbrev-ref HEAD)\", \"c\":\"$(git rev-parse HEAD)\"}"
  EOC
  ]
}

resource "null_resource" "deploy_function" {
  triggers = {
    fnversion = local.fndata.version
  }
  provisioner "local-exec" {
    working_dir = local.fnroot
    command     = <<-EOC
      fn build
      fn push
    EOC
  }
}

resource "oci_functions_function" "function" {
  depends_on         = [null_resource.deploy_function]
  application_id     = var.application
  display_name       = local.fndata.name
  image              = local.fndata.image
  memory_in_mbs      = local.fndata.memory
  timeout_in_seconds = local.fndata.timeout
  freeform_tags = {
    Branch = data.external.git_data.result.b
    Commit = data.external.git_data.result.c
  }
}

output "function_ocid" {
  value = oci_functions_function.function.id
}