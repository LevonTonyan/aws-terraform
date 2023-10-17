variable "public_subnet_cidrs" {
  type = list(string)
  description = "Public subnet CIDR values"
  default = [ "10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24" ]
}



variable "azs" {
  type = list(string)
  description = "Availability Zones"
  default = ["us-east-1a", "us-east-1b", "us-east-1c",]
}

variable "region" {
  type =string
  description = "Region"
  default = "us-east-1"
}