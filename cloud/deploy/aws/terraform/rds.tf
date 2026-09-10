resource "aws_security_group" "rds_sg" {
    name = "${var.project_name}-rds-sg"
    description = "Accesso di PostgreSQL dalla VPC"

    vpc_id = aws_vpc.main.id

    ingress {
        from_port = 5432
        to_port = 5432
        protocol = "tcp"
        cidr_blocks = [var.vpc_cidr]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "${var.project_name}-rds-sg"
    }
}

resource "aws_db_subnet_group" "rds_subnet_group" {
    name = "${var.project_name}-db-subnet-group"
    subnet_ids = [for subnet in aws_subnet.private : subnet.id]

    tags = {
        Name = "${var.project_name}-db-subnet-group"
    }
}

resource "aws_db_instance" "postgres" {
    identifier = "${var.project_name}-db"
    engine = "postgres"
    engine_version = "15"
    instance_class = "db.t3.micro"
    allocated_storage = 20
    storage_type = "gp2"
    db_name = "gcndatabase"
    username = "dbadmin"
    password = "SuperSecretPassword123!"
    skip_final_snapshot = true
    publicly_accessible = false
    db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name
    vpc_security_group_ids = [aws_security_group.rds_sg.id]



    tags = {
        Name = "${var.project_name}-postgres"
    }
}