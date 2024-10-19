
resource "aws_s3_bucket" "S3" {
  bucket = "my-first-tf-created-bucket-843"

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}