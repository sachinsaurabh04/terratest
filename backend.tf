terraform {
  backend "s3" {
    bucket       = "terraform-remote-state26"
    key          = "terratest/day-1/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
