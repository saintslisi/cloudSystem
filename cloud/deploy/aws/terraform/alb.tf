resource "aws_security_group" "alb_sg" {
    name = "${var.project_name}-alb-sg"
    description = "Security group per Application Load Balancer"
    vpc_id = aws_vpc.main.id


    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "${var.project_name}-alb-sg"
    }
}

