terraform {
  required_version = ">= 1.5"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.40"
    }
  }
}

# Reads DIGITALOCEAN_TOKEN for the API, and SPACES_ACCESS_KEY_ID plus
# SPACES_SECRET_ACCESS_KEY for bucket operations, from the environment.
provider "digitalocean" {}

# Survives `workbench llm down`. Only the droplet is disposable.
resource "digitalocean_spaces_bucket" "llm_cache" {
  name   = var.cache_bucket_name
  region = var.spaces_region
  acl    = "private"

  # A failed 17 GB multipart upload would bill silently forever.
  lifecycle_rule {
    id                                     = "abort-incomplete-multipart"
    enabled                                = true
    abort_incomplete_multipart_upload_days = 1
  }
}

# The droplet gets this key, scoped to the one bucket, not an account-wide key.
resource "digitalocean_spaces_key" "llm_droplet" {
  name = "agent-llm-cache"

  grant {
    bucket     = digitalocean_spaces_bucket.llm_cache.name
    permission = "readwrite"
  }
}

resource "digitalocean_ssh_key" "workbench" {
  name       = var.ssh_key_name
  public_key = file(pathexpand(var.ssh_public_key_path))
}

resource "digitalocean_tag" "llm" {
  name = var.droplet_tag
}

# Zero inbound. The only way in is the tailnet, which runs over outbound
# connections.
resource "digitalocean_firewall" "llm" {
  name = "agent-llm-no-inbound"
  tags = [digitalocean_tag.llm.name]

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

