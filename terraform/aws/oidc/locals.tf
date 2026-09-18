locals {
  region = "eu-central-1"
  tags = {
    ManagedBy = "terraform"
    App       = local.name
  }
  name             = "box"
  resources_bucket = "b-zago-resources"
}
