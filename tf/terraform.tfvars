# Copyright (c)  2022,  Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.



functions_app = {
  subnet          = "10.10.10.0/24"
  appname         = "oci-apigw-ords-auth_tf"
  pathprefix      = "/oci-apigw-ords-auth_tf"
  syslogurl       = null
  gateway_id      = null
  config_template = "appconfig.tmpl"
}

functions = [
  {
    fnpath  = "../oci-apigw-ords-auth"
    path    = "/oci-apigw-ords-auth"
    methods = ["GET"]
  }
]
