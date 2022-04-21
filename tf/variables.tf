# Copyright (c)  2022,  Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.


variable "ords_url" {
    description = "The ORDS Path"
    type = string
}

variable "compartment" {
  description = <<EOD
  Target OCI compartment OCID, defaults to the compartment-id from the fn context yaml file
  EOD
  type        = string
  default     = null
}

variable "fn_context" {
  description = <<EOD
  FN context, defaults to the "current-context" from the fn config.yaml file
  EOD
  type        = string
  default     = null
}

variable "fn_config_dir" {
  description = <<EOD
  FN configuration directory. Defaults to ~/.fn/ - this is expanded using the pathexpand operation to a valid home directory path
  EOD
  type        = string
  default     = "~/.fn/"
  validation {
    condition     = fileexists("${pathexpand(var.fn_config_dir)}/config.yaml")
    error_message = "The fn config directory and config.yaml file must exist."
  }
  validation {
    condition     = !fileexists("${pathexpand(var.fn_config_dir)}/config.yaml") || can(yamldecode(file("${pathexpand(var.fn_config_dir)}/config.yaml")).current-context)
    error_message = "The fn config file must contain a context entry."
  }
}

variable "functions_app" {
  description = <<EOD
  Function application configuration
    gateway_id: an optional OCID for an existing persistent API gateway instance (set to null for a terraform managed gateway for this application)
    subnet: CIDR syntax subnet for VCN, if you're not associating an existing API gateway and other networking
    appname: the name of the function application
    pathprefix: the base path prefix in API gateway for all functions under this application
    syslogurl: a syslog URL for sending logs to (optional - set to null for nothing)
    config_template: a template file for populating app configuration
  EOD
  type = object({
    gateway_id      = string
    subnet          = string
    appname         = string
    pathprefix      = string
    syslogurl       = string
    config_template = string
  })
}

variable "functions" {
  description = <<EOD
  List of function definitions
    fnpath: path to subdirectory containing a function definition
    path: relative subpath for this function within API gateway
    methods: list of HTTP methods at API gateway (an empty list will not generate an API gateway route)
  EOD
  type = set(object({
    fnpath  = string
    path    = string
    methods = list(string)
  }))
  validation {
    condition     = !contains([for func in var.functions : fileexists("${func.fnpath}/func.yaml")], false)
    error_message = "Not able to find valid func.yaml file."
  }
}

# Set up some locals for later reference
locals {
  functions   = toset(var.functions)
  functionmap = { for func in local.functions : basename(func.fnpath) => func }
}

# read the function config and profile from config to set some variables
locals {
  fnprofile   = var.fn_context != null ? var.fn_context : yamldecode(file("${pathexpand(var.fn_config_dir)}/config.yaml")).current-context
  rawctxdata  = yamldecode(file("${pathexpand(var.fn_config_dir)}/contexts/${local.fnprofile}.yaml"))
  compartment = var.compartment != null ? var.compartment : local.rawctxdata["oracle.compartment-id"] # default compartment to one configured in fn profile
  profile     = var.profile_name != null ? var.profile_name : local.rawctxdata["oracle.profile"]      # default profile name to the one in the fn profile
  registry    = local.rawctxdata["registry"]
}

