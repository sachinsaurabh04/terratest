provider "aws" {
  region = "us-east-2"
  AWS_ACCESS_KEY_ID = "AKIAQLVQQVLYJ5ESV4FN"
  AWS_SECRET_ACCESS_KEY = "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"
}

resource "aws_instance" "webserver" {
  ami           = "ami-050cd642fd83388e4"
  instance_type = "t2.micro"
  tags = {
    Name = "webserver"
  }
}