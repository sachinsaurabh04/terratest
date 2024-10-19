provider "aws" {
  region = "us-east-2"
}

resource "aws_instance" "webserver" {
  ami           = "ami-050cd642fd83388e4"
  instance_type = "t2.micro"
  tags = {
    Name = "webserver"
  }
}