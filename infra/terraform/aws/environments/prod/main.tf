provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

data "aws_caller_identity" "current" {}

locals {
  name = "${var.project}-${var.environment}"
  tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
  uploads_bucket_name = "${var.project}-${var.environment}-uploads-${data.aws_caller_identity.current.account_id}"
}

module "network" {
  source = "../../modules/network"

  name                 = local.name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  tags                 = local.tags
}

module "security" {
  source = "../../modules/security"

  name              = local.name
  vpc_id            = module.network.vpc_id
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  tags              = local.tags
}

module "ecr" {
  source = "../../modules/ecr"

  name = local.name
  tags = local.tags
}

module "uploads_bucket" {
  source = "../../modules/uploads_bucket"

  bucket_name = local.uploads_bucket_name
  tags        = local.tags
}

data "aws_iam_policy_document" "app_s3_access" {
  statement {
    sid = "AllowListBucket"

    actions = [
      "s3:ListBucket"
    ]

    resources = [
      module.uploads_bucket.bucket_arn
    ]
  }

  statement {
    sid = "AllowObjectCRUD"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [
      "${module.uploads_bucket.bucket_arn}/*"
    ]
  }
}

resource "aws_iam_policy" "app_s3_access" {
  name   = "${local.name}-app-s3-access"
  policy = data.aws_iam_policy_document.app_s3_access.json

  tags = local.tags
}

module "app_server" {
  source = "../../modules/app_server"

  name              = local.name
  ami_id            = var.ec2_ami_id
  instance_type     = var.ec2_instance_type
  subnet_id         = module.network.public_subnet_ids[0]
  security_group_id = module.security.app_security_group_id
  key_pair_name     = var.key_pair_name
  additional_policy_arns = {
    s3_access = aws_iam_policy.app_s3_access.arn
  }
  tags = local.tags
}

resource "aws_eip" "app" {
  domain = "vpc"

  tags = merge(local.tags, {
    Name = "${local.name}-app-eip"
  })
}

resource "aws_eip_association" "app" {
  instance_id   = module.app_server.instance_id
  allocation_id = aws_eip.app.id
}

module "rds" {
  count  = var.create_rds ? 1 : 0
  source = "../../modules/rds"

  name                  = local.name
  private_subnet_ids    = module.network.private_subnet_ids
  security_group_id     = module.security.db_security_group_id
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  db_name               = var.db_name
  db_username           = var.db_username
  db_password           = var.db_password
  backup_retention_days = var.db_backup_retention_days
  tags                  = local.tags
}

resource "aws_route53_record" "app" {
  count = var.route53_zone_id != "" && var.app_hostname != "" ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.app_hostname
  type    = "A"
  ttl     = 60
  records = [aws_eip.app.public_ip]
}
