#  Copyright (c) 2022 Oracle
#  Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/

# Managed API Gateway
# If you don't reference an existing API Gateway OCID in the functions_app variable (by setting it to null) then we'll create and
# manage a gateway for you. This entails creating other networking resources such as a VCN as well.
resource "oci_apigateway_gateway" "managed_api_gateway" {
  count          = var.functions_app.gateway_id != null ? 0 : 1
  compartment_id = local.compartment
  endpoint_type  = "PUBLIC"
  subnet_id      = oci_core_subnet.subnet[0].id
  lifecycle {
    prevent_destroy = false
  }
  display_name = "oci-apigw-ords-auth"
}


# Core network

resource "oci_core_vcn" "virtual_network" {
  count          = var.functions_app.gateway_id != null ? 0 : 1
  cidr_block     = var.functions_app.subnet
  compartment_id = local.compartment
}

resource "oci_core_internet_gateway" "internet_gateway" {
  count          = var.functions_app.gateway_id != null ? 0 : 1
  compartment_id = local.compartment
  vcn_id         = oci_core_vcn.virtual_network[0].id
}

resource "oci_core_default_route_table" "route_table" {
  count                      = var.functions_app.gateway_id != null ? 0 : 1
  manage_default_resource_id = oci_core_vcn.virtual_network[0].default_route_table_id

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.internet_gateway[0].id
  }
}

resource "oci_core_default_security_list" "security_list" {
  count                      = var.functions_app.gateway_id != null ? 0 : 1
  manage_default_resource_id = oci_core_vcn.virtual_network[0].default_security_list_id

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    stateless   = false
  }

  // allow inbound icmp traffic of a specific type
  ingress_security_rules {
    protocol  = 1
    source    = oci_core_vcn.virtual_network[0].cidr_block
    stateless = false

    icmp_options {
      type = 3
    }
  }

  ingress_security_rules {
    protocol = "6"
    // tcp
    source    = "0.0.0.0/0"
    stateless = false

    tcp_options {
      min = 443
      max = 443
    }
  }
}

resource "oci_core_subnet" "subnet" {
  count          = var.functions_app.gateway_id != null ? 0 : 1
  cidr_block     = var.functions_app.subnet
  compartment_id = local.compartment
  vcn_id         = oci_core_vcn.virtual_network[0].id
}

