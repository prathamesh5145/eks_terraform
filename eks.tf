provider "aws" {
  region = "us-east-1"
}

#creating roles
resource "aws_iam_role" "rolecluster" {
  name = "eks-role" 
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}
resource "aws_iam_role" "noderole" {
  name = "node-role"
    assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

#attaching policy to roles
resource "aws_iam_role_policy_attachment" "cluster-policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role = aws_iam_role.rolecluster.name
}
resource "aws_iam_role_policy_attachment" "node-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role = aws_iam_role.noderole.name
}
resource "aws_iam_role_policy_attachment" "node-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role = aws_iam_role.noderole.name
}
resource "aws_iam_role_policy_attachment" "node-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role = aws_iam_role.noderole.name
}

#createing vpc
resource "aws_vpc" "eks-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "eks-vpc"
  }
}

#creating internet gatway
resource "aws_internet_gateway" "eks-igw" {
  vpc_id = aws_vpc.eks-vpc.id
  tags = {
    Name = "eks-igw"
  }
}

#creating subnets
resource "aws_subnet" "public-1a"{
    vpc_id = aws_vpc.eks-vpc.id
    availability_zone = "us-east-1a"
    map_public_ip_on_launch = true
    cidr_block = "10.0.0.0/19"
    tags = {
      Name = "public-1a"
    }
}
resource "aws_subnet" "public-1b"{
    vpc_id = aws_vpc.eks-vpc.id
    availability_zone = "us-east-1b"
    map_public_ip_on_launch = true
    cidr_block = "10.0.32.0/19"
    tags = {
      Name = "puclic-1b"
    }
}
resource "aws_subnet" "public-1c"{
    vpc_id = aws_vpc.eks-vpc.id
    availability_zone = "us-east-1c"
    map_public_ip_on_launch = true
    cidr_block = "10.0.64.0/19"
    tags = {
      Name = "public-1c"
    }
}

#creating route table
resource "aws_route" "eks-routetable-private" {
  route_table_id = aws_vpc.eks-vpc.default_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.eks-igw.id
}
resource "aws_route" "eks-routetable-public" {
  route_table_id = aws_vpc.eks-vpc.default_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.eks-igw.id
}

#subnet association in RT
resource "aws_route_table_association" "public-1a" {
  subnet_id = aws_subnet.public-1a.id
  route_table_id = aws_vpc.eks-vpc.default_route_table_id
}
resource "aws_route_table_association" "public-1b" {
  subnet_id = aws_subnet.public-1b.id
  route_table_id = aws_vpc.eks-vpc.default_route_table_id
}
resource "aws_route_table_association" "public-1c" {
  subnet_id = aws_subnet.public-1c.id
  route_table_id = aws_vpc.eks-vpc.default_route_table_id
}

#creating NAT Gtw
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = {
    Name = "nat"
  }
}
resource "aws_nat_gateway" "eks-nat" {
  allocation_id = aws_eip.nat.id
  subnet_id = aws_subnet.public-1c.id
  tags = {
    Name = "eks-nat"
  }
  depends_on = [ aws_internet_gateway.eks-igw ]
}

#creating security group
resource "aws_security_group" "eks-sg" {
  name = "eks-sg"
  description = "sg-for-eks"
  vpc_id = aws_vpc.eks-vpc.id
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    protocol = "-1"
    from_port = 0
    to_port = 0
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    protocol = "-1"
    from_port = 0
    to_port = 0
  }
}

#creating eks
resource "aws_eks_cluster" "cluster" {
  name = "prathamesh"
  role_arn = aws_iam_role.rolecluster.arn
  vpc_config {
    subnet_ids = [
        aws_subnet.public-1a.id,
        aws_subnet.public-1b.id,
        aws_subnet.public-1c.id
    ]
  }
  depends_on = [ aws_iam_role_policy_attachment.cluster-policy ]
}

#creating nodes
resource "aws_eks_node_group" "prathamesh-node" {
  cluster_name = aws_eks_cluster.cluster.name
  node_group_name = "prathamesh"
  node_role_arn = aws_iam_role.noderole.arn
  subnet_ids = [
    aws_subnet.public-1a.id,
    aws_subnet.public-1b.id,
    aws_subnet.public-1c.id
  ]
  capacity_type = "ON_DEMAND"
  instance_types = ["t3.small"]
  scaling_config {
    desired_size = 2
    min_size = 1
    max_size = 4
  }
  update_config {
    max_unavailable = 1
  }
  depends_on = [ 
    aws_iam_role_policy_attachment.node-AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.node-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node-AmazonEKS_CNI_Policy
  ]
}