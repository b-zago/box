module "providers" {
  for_each = var.clusters

  source           = "github.com/b-zago/terraforming/aws/modules/oidc_provisioner"
  resources_bucket = local.resources_bucket
  bucket_path      = "oidc/${each.key}"
  region           = local.region
  subjects         = each.value
}
