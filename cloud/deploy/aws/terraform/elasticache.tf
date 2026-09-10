resource "aws_security_group" "redis_sg" {
    name = "${var.project_name}-redis-sg"
    vpc_id = aws_vpc.main.id

    ingress {
        description = "Redis access"
        from_port = 6379
        to_port = 6379
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
        Name = "${var.project_name}-redis-sg"
    }
}

resource "aws_elasticache_subnet_group" "reids_subnet_group" {
    name = "${var.project_name}-redis-subnet-group"
    subnet_ids = [for subnet in aws_subnet.private : subnet.id]
}

resource "aws_elasticache_cluster" "redis" {
    cluster_id = "${var.project_name}-redis"
    engine = "redis"
    node_type = "cache.t4g.micro"
    num_cache_nodes = 1
    parameter_group_name = "default.redis7"
    engine_version = "7.1"
    port = 6379
    subnet_group_name = aws_elasticache_subnet_group.reids_subnet_group.name
    security_group_ids = [aws_security_group.redis_sg.id]
    tags = {
        Name = "${var.project_name}-redis"
    }
}
