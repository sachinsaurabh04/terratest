resource "local_file" "foo" {
  content  = "This is my first terraform code on centos 8."
  filename = "${path.module}/testfile"
}
