# Copyright (c)  2022,  Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.

resource "oci_functions_application" "fn_application" {
  compartment_id = local.compartment
  syslog_url     = var.functions_app.syslogurl
  display_name   = var.functions_app.appname
  subnet_ids     = [data.oci_apigateway_gateway.api_gateway.subnet_id]
  config = jsondecode(templatefile(var.functions_app.config_template, {
    apigw = data.oci_apigateway_gateway.api_gateway
    fnapp = var.functions_app
    fn    = local.functionmap
    back_end_client_secret_ocid = data.oci_vault_secrets.back_end_client_secret.secrets[0].id,
    idcs_app_client_secret_ocid = data.oci_vault_secrets.idcs_app_client_secret.secrets[0].id
  }))

}

module "functions" {
  source       = "./modules/fn"
  for_each     = local.functionmap
  function     = each.value
  compartment  = local.compartment
  functionsapp = var.functions_app
  application  = oci_functions_application.fn_application.id
  registry     = local.registry
}