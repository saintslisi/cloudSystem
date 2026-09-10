resource "aws_security_group" "k8s_nodes" {
    name = "${var.project_name}-k8s-sg"
    description = "Firewall per le macchine k8s"

    vpc_id = aws_vpc.main.id

    # Rule Ingress
    #SSH from anywhere
    ingress{
        description = "SSH from anywhere"

        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    # Nodeport traffic for Web UI
    ingress{
        description = "NodePort traffic for Web UI"

        from_port = 30000
        to_port = 32767
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]

    }

    # Kube API Server
    ingress{
        description = "Kubernetes API Server"

        from_port = 6443
        to_port = 6443
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    # Server traffic
    ingress {
        description = "inner vpc traffic"
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = [var.vpc_cidr]
    }

    # Rule Egress
    # Server use internet
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "${var.project_name}-k8s-sg"
    }

}