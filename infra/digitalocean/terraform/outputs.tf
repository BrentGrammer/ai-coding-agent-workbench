output "cache_bucket" {
  description = "Bucket name for DIGITALOCEAN_LLM_CACHE_BUCKET in digitalocean-llm.env"
  value       = digitalocean_spaces_bucket.llm_cache.name
}

output "spaces_region" {
  description = "Region for DIGITALOCEAN_SPACES_REGION in digitalocean-llm.env"
  value       = digitalocean_spaces_bucket.llm_cache.region
}

output "spaces_access_key_id" {
  description = "Bucket-scoped key for SPACES_ACCESS_KEY_ID in digitalocean-llm.env"
  value       = digitalocean_spaces_key.llm_droplet.access_key
  sensitive   = true
}

output "spaces_secret_access_key" {
  description = "Bucket-scoped secret for SPACES_SECRET_ACCESS_KEY in digitalocean-llm.env"
  value       = digitalocean_spaces_key.llm_droplet.secret_key
  sensitive   = true
}

output "droplet_tag" {
  description = "Tag the firewall targets. bin/workbench applies it to every droplet."
  value       = digitalocean_tag.llm.name
}

