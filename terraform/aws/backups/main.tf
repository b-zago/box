terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = "eu-central-1"

  default_tags {
    tags = {
      ManagedBy = "terraform"
      App       = "box"
    }
  }
}

variable "bucket_name" {
  type    = string
  default = "b-zago-pgsql-backups"
}

variable "retention_days" {
  type    = number
  default = 14
}

resource "aws_s3_bucket" "backups" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "backups" {
  bucket = aws_s3_bucket.backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "expire-old-backups"
    status = "Enabled"

    filter {
      prefix = "pgsql/"
    }

    expiration {
      days = var.retention_days
    }
  }
}

# The prod postgresql-admin role (created in ../oidc) may only add prod backups.
resource "aws_iam_role_policy" "backup" {
  name = "pgsql-backups-s3"
  role = "metal_prod_pgsql_role"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.backups.arn}/pgsql/prod/*"
    }]
  })
}
