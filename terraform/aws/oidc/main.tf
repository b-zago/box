module "providers" {
  for_each = var.clusters

  source           = "github.com/b-zago/terraforming/aws/modules/oidc_provisioner"
  resources_bucket = local.resources_bucket
  bucket_path      = "oidc/${each.key}"
  role_name        = "metal_${each.key}_role"
  region           = local.region
}
