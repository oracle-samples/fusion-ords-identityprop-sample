#  Copyright (c) 2022 Oracle
#  Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

data "oci_apigateway_gateway" "api_gateway" {
  gateway_id = var.functions_app.gateway_id != null ? var.functions_app.gateway_id : oci_apigateway_gateway.managed_api_gateway[0].id
}

output "api_gateway" {
  value = {
    ips      = data.oci_apigateway_gateway.api_gateway.ip_addresses
    hostname = data.oci_apigateway_gateway.api_gateway.hostname
  }
}

resource "oci_apigateway_deployment" "api_gateway_deployment" {
  compartment_id = local.compartment
  gateway_id     = data.oci_apigateway_gateway.api_gateway.id
  path_prefix    = var.functions_app.pathprefix

  specification {
    request_policies {
        authentication {
            type = "CUSTOM_AUTHENTICATION"
            function_id= module.functions["oci-apigw-ords-auth"].function_ocid
            token_header = "Authorization"
        }
    }

    logging_policies {
      access_log {
        is_enabled = true
      }
      execution_log {
        is_enabled = true
      }
    }
    routes {
        path = "/ords/{foo}"
        backend {
            type="HTTP_BACKEND"
            url=var.ords_url
            connect_timeout_in_seconds = "5"
            is_ssl_verify_disabled = true
            read_timeout_in_seconds ="5"
            send_timeout_in_seconds= "5"
        }
        methods=["GET","POST","PATCH","DELETE"]
        request_policies {
            header_transformations {
                set_headers {
                    items {
                            name = "Authorization"
                            values = ["$${request.auth[back_end_token]}"]
                            if_exists = "OVERWRITE"
                        }
                     items {
                            name = "X-AUTH-FUSION-ROLES"
                            values = ["$${request.auth[fusion_roles]}"]
                            if_exists = "OVERWRITE"
                        }
                     items {
                            name = "X-AUTH-USERNAME"
                            values = ["$${request.auth[ords_username]}"]
                            if_exists = "OVERWRITE"
                        }

                }
            }




        }
    }
  }
}

output "function_endpoints" {
  value = { for func in local.functions : basename(func.fnpath) => "${oci_apigateway_deployment.api_gateway_deployment.endpoint}${func.path}" if length(func.methods) > 0 && func.path != null }
}

#resource "oci_identity_policy" "api_gateway_fnpolicy" {
#  compartment_id = local.compartment
#  description    = "APIGW policy for compartment to access FN"
#  name           = "apigateway_fn_policies"
#  statements = [
#    "ALLOW any-user to use functions-family in compartment id ${local.compartment} where ALL {request.principal.type= 'ApiGateway', request.resource.compartment.id = '${local.compartment}'}"
#  ]
#}