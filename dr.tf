# Disaster Recovery backbone: S3 cross-region replication,
# RDS read replica, and Route 53 failover records.
# Provider aliases: aws (primary), aws.dr (DR region).

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" { region = "ap-southeast-1" }              # primary
provider "aws" { alias = "dr", region = "ap-southeast-3" } # DR region

variable "enable_dr" {
  description = "Stand up DR-region resources (costs money when true)"
  type        = bool
  default     = false
}

# ---------- S3: versioning + cross-region replication ----------

resource "aws_s3_bucket" "primary" { bucket = "app-data-primary" }

resource "aws_s3_bucket_versioning" "primary" {
  bucket = aws_s3_bucket.primary.id
  versioning_configuration { status = "Enabled" } # replication requires this
}

resource "aws_s3_bucket" "dr" {
  provider = aws.dr
  count    = var.enable_dr ? 1 : 0
  bucket   = "app-data-dr"
}

resource "aws_s3_bucket_versioning" "dr" {
  provider = aws.dr
  count    = var.enable_dr ? 1 : 0
  bucket   = aws_s3_bucket.dr[0].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_iam_role" "replication" {
  count = var.enable_dr ? 1 : 0
  name  = "s3-crr-dr-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "s3.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_s3_bucket_replication_configuration" "dr" {
  count  = var.enable_dr ? 1 : 0
  role   = aws_iam_role.replication[0].arn
  bucket = aws_s3_bucket.primary.id

  rule {
    id     = "to-dr-region"
    status = "Enabled"
    destination {
      bucket        = aws_s3_bucket.dr[0].arn
      storage_class = "STANDARD"
    }
  }
  depends_on = [aws_s3_bucket_versioning.primary]
}

# ---------- RDS: primary + promotable read replica ----------

resource "aws_db_instance" "primary" {
  identifier          = "app-db-primary"
  engine              = "postgres"
  engine_version      = "16"
  instance_class      = "db.t4g.medium"
  allocated_storage   = 100
  username            = "app"
  manage_master_user_password = true
  backup_retention_period     = 7
  skip_final_snapshot         = false
}

# The "pilot light": promote this to a standalone primary on failover.
resource "aws_db_instance" "dr_replica" {
  provider            = aws.dr
  count               = var.enable_dr ? 1 : 0
  identifier          = "app-db-dr-replica"
  replicate_source_db = aws_db_instance.primary.arn
  instance_class      = "db.t4g.medium"
  skip_final_snapshot = true
}

# ---------- Route 53: health check + failover records ----------

resource "aws_route53_health_check" "primary" {
  count             = var.enable_dr ? 1 : 0
  fqdn              = "app.example.com"
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30
  tags = { Name = "primary-health-check" }
}

resource "aws_route53_record" "primary" {
  count   = var.enable_dr ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = "app.example.com"
  type    = "A"

  set_identifier = "primary"
  failover_routing_policy { type = "PRIMARY" }
  health_check_id = aws_route53_health_check.primary[0].id
  alias {
    name                   = aws_lb.primary.dns_name
    zone_id                = aws_lb.primary.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "secondary" {
  count   = var.enable_dr ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = "app.example.com"
  type    = "A"

  set_identifier = "dr-secondary"
  failover_routing_policy { type = "SECONDARY" }
  alias {
    name                   = aws_lb.dr[0].dns_name
    zone_id                = aws_lb.dr[0].zone_id
    evaluate_target_health = true
  }
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone for app.example.com"
  type        = string
  default     = "Z0123456789EXAMPLE"
}

# NOTE: aws_lb.primary / aws_lb.dr are referenced but defined in the
# application's own networking module — wire your ALBs in here.
