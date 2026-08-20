variable "cache_bucket_name" {
  description = "Spaces bucket for the cached Ollama model. Names are global across all of Spaces, so change this if the default is taken."
  type        = string
  default     = "agent-workbench-llm-cache"
}

variable "spaces_region" {
  description = "Region for the cache bucket. Spaces has no Toronto region, so NYC3 is the closest to the TOR1 droplets."
  type        = string
  default     = "nyc3"
}

variable "droplet_tag" {
  description = "Tag the firewall targets and bin/workbench filters on. Every GPU droplet must carry it."
  type        = string
  default     = "agent-workbench-gpu-llm"
}

variable "ssh_key_name" {
  description = "Name of the SSH key in the DigitalOcean account. bin/workbench looks it up by this name at droplet create."
  type        = string
  default     = "agent-workbench"
}

variable "ssh_public_key_path" {
  description = "Path to the local SSH public key to register."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

