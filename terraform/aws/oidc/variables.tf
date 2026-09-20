variable "clusters" {
  type = map(map(object({
    sub       = string
    ssm_paths = list(string)
  })))
}
