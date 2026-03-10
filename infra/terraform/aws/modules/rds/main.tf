resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db-subnets"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.name}-db-subnets"
  })
}

resource "aws_db_instance" "this" {
  identifier             = "${var.name}-postgres"
  engine                 = "postgres"
  instance_class         = var.instance_class
  allocated_storage      = var.allocated_storage
  max_allocated_storage  = var.max_allocated_storage
  storage_type           = "gp3"
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  backup_retention_period = var.backup_retention_days
  maintenance_window      = "Mon:01:00-Mon:02:00"
  backup_window           = "03:00-04:00"

  publicly_accessible   = false
  storage_encrypted     = true
  multi_az              = false
  deletion_protection   = false
  skip_final_snapshot   = true
  apply_immediately     = true
  copy_tags_to_snapshot = true

  tags = merge(var.tags, {
    Name = "${var.name}-postgres"
  })
}
