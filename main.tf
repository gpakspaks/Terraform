data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # ✅ 2AZ 고정
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  name_prefix = var.project
  tags = {
    Project = var.project
    Managed = "terraform"
  }
}

#-----------------------
# VPC
#-----------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-igw"
  })
}

#-----------------------
# Subnets
# - AZ는 2개로 고정하고, idx % 2 로 번갈아 배치
#-----------------------
resource "aws_subnet" "public" {
  for_each = { for idx, cidr in var.subnet_cidrs.public : idx => cidr }

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = local.azs[tonumber(each.key) % length(local.azs)]
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-public-${tonumber(each.key) + 1}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  for_each = { for idx, cidr in var.subnet_cidrs.private : idx => cidr }

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = local.azs[tonumber(each.key) % length(local.azs)]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-private-${tonumber(each.key) + 1}"
    Tier = "private"
  })
}

#-----------------------
# Route table - Public
#-----------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-rtb-public"
  })
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

#-----------------------
# NAT Gateway (Private egress)
# - Public subnet 첫 번째에 NAT 1개만 구성(비용 절감형)
#   (고가용성 원하면 NAT를 AZ별 2개로 확장 가능)
#-----------------------
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${local.name_prefix}-nat-eip" })
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = values(aws_subnet.public)[0].id

  tags = merge(local.tags, { Name = "${local.name_prefix}-nat" })

  depends_on = [aws_internet_gateway.this]
}

#-----------------------
# Route table - Private
#-----------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-rtb-private"
  })
}

resource "aws_route" "private_default" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

#-----------------------
# Bastion Security Group
#-----------------------
resource "aws_security_group" "bastion" {
  name        = "${local.name_prefix}-bastion-sg"
  description = "Bastion SG"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.bastion_allowed_cidrs
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-bastion-sg"
  })
}

#-----------------------
# AMI (Amazon Linux 2023)
#-----------------------
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

#-----------------------
# Bastion EC2
# - Public subnet 첫 번째에 생성
#-----------------------
resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.bastion_instance_type
  subnet_id              = values(aws_subnet.public)[0].id
  vpc_security_group_ids = [aws_security_group.bastion.id]
  key_name               = var.bastion_key_name

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-bastion"
  })
}