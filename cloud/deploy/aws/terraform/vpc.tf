# Rete VPC Principale
resource "aws_vpc" "main" {
    cidr_block = var.vpc_cidr
    enable_dns_hostnames = true
    enable_dns_support = true

    tags = {
        Name = "${var.project_name}-vpc"
    }
}

# Zone disponibili dinamiche
data "aws_availability_zones" "available" {
    state = "available"
}

# Creazione 2 subnet pubbliche
resource "aws_subnet" "public" {
    count = 2
    vpc_id = aws_vpc.main.id
    cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index)
    availability_zone = data.aws_availability_zones.available.names[count.index]
    map_public_ip_on_launch = true

    tags = {
        Name = "${var.project_name}-public-${count.index}"
    }
}

# Creazione 2 subnet private
resource "aws_subnet" "private" {
    count = 2
    vpc_id = aws_vpc.main.id
    cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index + 2)
    availability_zone = data.aws_availability_zones.available.names[count.index]

    tags = {
        Name = "${var.project_name}-private-${count.index}"
    }
}

# Gateway pubblico
resource "aws_internet_gateway" "main" {
    vpc_id = aws_vpc.main.id

    tags = {
        Name = "${var.project_name}-igw"
    }
}

# public subnet
resource "aws_route_table" "public" {
    vpc_id = aws_vpc.main.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.main.id
    }

    tags = {
        Name = "${var.project_name}-rt-public"
    }
}

# route table per le subnet private
resource "aws_route_table_association" "public" {
    count = 2
    subnet_id = aws_subnet.public[count.index].id
    route_table_id = aws_route_table.public.id
}

# IP Fisso NAT Gateway
resource "aws_eip" "nat" {
    domain = "vpc"
    tags = {
        Name = "${var.project_name}-nat-eip"
    }   
}

# NAT Gateway
resource "aws_nat_gateway" "main" {
    allocation_id = aws_eip.nat.id
    subnet_id = aws_subnet.public[0].id
    depends_on = [aws_internet_gateway.main]

    tags = {
        Name = "${var.project_name}-nat"
    }
}

#route table per le subnet private
resource "aws_route_table" "private" {
    vpc_id = aws_vpc.main.id

    route {
        cidr_block = "0.0.0.0/0"
        nat_gateway_id = aws_nat_gateway.main.id
    }

    tags = {
        Name = "${var.project_name}-rt-private"
    }
}

# route table association
resource "aws_route_table_association" "private" {
    count = 2
    subnet_id = aws_subnet.private[count.index].id
    route_table_id = aws_route_table.private.id
}

resource "aws_lb" "main" {
    name = "${var.project_name}-alb"
    internal = false
    load_balancer_type = "application"
    security_groups = [aws_security_group.alb_sg.id]
    subnets = [for subnet in aws_subnet.public : subnet.id]

    tags = {
        Name = "${var.project_name}-alb"
    }
}

resource "aws_lb_target_group" "web" {
    name = "${var.project_name}-web-tg"
    port = "80"
    protocol = "HTTP"
    vpc_id = aws_vpc.main.id

    health_check {
        path = "/"
        healthy_threshold = 2
        unhealthy_threshold = 10
        timeout = 5
        interval = 10
        matcher = "200-499"
    }
}

resource "aws_lb_listener" "http" {
    load_balancer_arn = aws_lb.main.arn
    port = "80"
    protocol = "HTTP"

    default_action {
        type = "forward"
        target_group_arn = aws_lb_target_group.web.arn
    }
}


resource "aws_lb_target_group_attachment" "worker_1" {
    target_group_arn = aws_lb_target_group.web.arn
    target_id = aws_instance.k8s_worker_1.id
    port = 80
}

resource "aws_lb_target_group_attachment" "master" {
    target_group_arn = aws_lb_target_group.web.arn
    target_id = aws_instance.k8s_master.id
    port = 80
}
