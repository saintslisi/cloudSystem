resource "aws_s3_bucket" "data_bucket" {
    bucket = "${var.project_name}-data-santi"

    tags = {
        Name = "${var.project_name}-data-bucket"
    }
}

resource "aws_s3_bucket_public_access_block" "data_bucket_block" {
    bucket = aws_s3_bucket.data_bucket.id

    block_public_acls = true
    block_public_policy = true
    ignore_public_acls = true
    restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "data_versioning" {
    bucket = aws_s3_bucket.data_bucket.id
    
    versioning_configuration {
        status = "Enabled"
    }
}
