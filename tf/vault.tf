# Copyright (c)  2022,  Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.



resource "oci_kms_vault" "oci-apigw-ords-auth-vault" {
    compartment_id = local.compartment
    display_name = "oci-apigw-ords-auth-gtw"
    vault_type = "DEFAULT"
}

resource "oci_kms_key" "oci-apigw-ords-auth-vault-key" {
  compartment_id      = local.compartment
  display_name        = "oci-apigw-ords-auth-vault-key"
  management_endpoint = oci_kms_vault.oci-apigw-ords-auth-vault.management_endpoint

  key_shape {
    algorithm = "AES"
    length    = "16"
  }

  provisioner "local-exec" {
    command = <<-EOC
     oci vault secret create-base64 -c ${local.compartment} --secret-name "back_end_client_secret" --vault-id "${oci_kms_vault.oci-apigw-ords-auth-vault.id}" --key-id ${oci_kms_key.oci-apigw-ords-auth-vault-key.id} --secret-content-content "${base64encode(random_password.oci-apigw-ords-auth-vault-dummypassword.result)}"
    EOC
  }
  
  provisioner "local-exec" {
    command = <<-EOC
     oci vault secret create-base64 -c ${local.compartment} --secret-name "idcs_app_client_secret" --vault-id "${oci_kms_vault.oci-apigw-ords-auth-vault.id}" --key-id ${oci_kms_key.oci-apigw-ords-auth-vault-key.id} --secret-content-content "${base64encode(random_password.oci-apigw-ords-auth-vault-dummypassword.result)}"
    EOC
  }
}

# Generates a random password for seeding OCI
resource "random_password" "oci-apigw-ords-auth-vault-dummypassword" {
  length  = 16
  special = true
  min_lower = 1
  min_upper = 1
  min_numeric = 1
  min_special = 1
  override_special = "!$^.,"
}

data "oci_vault_secrets" "back_end_client_secret" {
    compartment_id = local.compartment
    name = "back_end_client_secret"
    vault_id = oci_kms_vault.oci-apigw-ords-auth-vault.id
    depends_on = [oci_kms_key.oci-apigw-ords-auth-vault-key]
}

data "oci_vault_secrets" "idcs_app_client_secret" {
    compartment_id = local.compartment
    name = "idcs_app_client_secret"
    vault_id = oci_kms_vault.oci-apigw-ords-auth-vault.id
    depends_on = [oci_kms_key.oci-apigw-ords-auth-vault-key]
}