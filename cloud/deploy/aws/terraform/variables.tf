variable "project_name" {
    description = "Nome del progetto"
    default = "sistemi-cloud"
}

variable "vpc_cidr" {
    description = "Spazio indirizzi IP della rete"
    default = "10.0.0.0/16"
}

variable "db_password" {
    description = "Password per il database RDS"
    type = string
    sensitive = true
}