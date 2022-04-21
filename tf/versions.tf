# Copyright (c)  2022,  Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl.


terraform {
  required_providers {
    oci = {
      source  = "hashicorp/oci"
      version = "~> 4.5.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.0.0"
    }
  }
  required_version = ">= 0.13"
}
