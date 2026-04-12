module "storage" {
  source                     = "../../stacks/storage"
  enable_deletion_protection = false
  point_in_time_recovery = {
    enabled = false
    days    = 35
  }
}

