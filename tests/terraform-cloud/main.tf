terraform {
  backend "remote" {
    organization = "flooktech"

    workspaces {
      prefix = "github-actions-"
    }
  }
  required_version = "0.13.0"
}

resource "random_id" "the_id" {
  byte_length = 5
}

variable "default" {
  default = "default"
}

output "default" {
  value = var.default
}

variable "from_tfvars" {
  default = "default"
}

output "from_tfvars" {
  value = var.from_tfvars
}

variable "from_variables" {
  default = "default"
}

output "from_variables" {
  value = var.from_variables
}
