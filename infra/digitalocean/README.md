# DigitalOcean GPU path

The fallback GPU provider for the local LLM, used when AWS has no 48 GB
capacity. The box serves the same model, joins the tailnet as `agent-llm`,
and exposes the same inference proxy on port 11435, so agents need no changes.

Layout:

- `terraform/` — the persistent pieces: the Spaces model-cache bucket, a
  bucket-scoped Spaces key, the zero-inbound firewall, and the SSH key.
  These survive `llm down`.
- `droplet/` — what runs on the disposable GPU droplet: setup, idle stop,
  and self-destroy.

## Billing rule

A powered-off GPU Droplet bills at the full rate (~$1.57/hr). The lifecycle
therefore only destroys, never stops. The idle stop and the 12-hour fuse both
destroy the droplet through the API. The Spaces subscription is a flat
$5/month while any bucket exists.

The idle stop destroys the droplet about **70 minutes** after the last
prompt, or **40 minutes** after boot if nothing ever prompts it. The fuse
destroys it **12 hours** after boot no matter what.

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install)
- [doctl](https://docs.digitalocean.com/reference/doctl/how-to/install/) cli for DigitalOcean

## One-time setup

1. Install the tools: 
```shell
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
brew install doctl
```
2. Create an API token (control panel: API → Tokens, full access).
   Run `doctl auth init` with it, and export it for Terraform:
   `export DIGITALOCEAN_TOKEN=...`
3. Create an admin Spaces key (control panel: Spaces Keys). Terraform needs
   it for bucket operations only:
   `export SPACES_ACCESS_KEY_ID=... SPACES_SECRET_ACCESS_KEY=...`
4. Apply the persistent pieces:

   ```bash
   terraform -chdir=infra/digitalocean/terraform init
   terraform -chdir=infra/digitalocean/terraform apply
   ```

   Read the bucket-scoped key it created for the droplet:

   ```bash
   terraform -chdir=infra/digitalocean/terraform output -raw spaces_access_key_id
   terraform -chdir=infra/digitalocean/terraform output -raw spaces_secret_access_key
   ```

5. Create the self-destroy token (control panel: API → Tokens → Custom
   Scopes). Give it only the droplet delete scope. The idle stop and the
   fuse use it from the box.
6. Reuse the GPU box Tailscale key: the reusable, ephemeral, signed key from
   `docs/cloud-onetime-setup.md` section 7.
7. Write `~/.config/agent-workbench/digitalocean-llm.env` with mode 600:

   ```
   DIGITALOCEAN_LLM_CACHE_BUCKET=agent-workbench-llm-cache
   DIGITALOCEAN_SPACES_REGION=nyc3
   SPACES_ACCESS_KEY_ID=<bucket-scoped key from terraform output>
   SPACES_SECRET_ACCESS_KEY=<bucket-scoped secret from terraform output>
   DIGITALOCEAN_LLM_DESTROY_TOKEN=<the custom-scoped token>
   TAILSCALE_AUTH_KEY=<the GPU box key>
   ```

## Use

```bash
WORKBENCH_LLM_PROVIDER=digitalocean workbench llm up
WORKBENCH_LLM_PROVIDER=digitalocean workbench llm status
WORKBENCH_LLM_PROVIDER=digitalocean workbench llm down
```

`llm up` tries the RTX 6000 Ada first, then the L40S — both 48 GB, both
TOR1 only — and takes the first with stock. Override the order or the list
with `WORKBENCH_LLM_DIGITALOCEAN_SIZES`.

## Terraform state

State stays local and gitignored, because Terraform writes resource secrets
(the Spaces keys) into `terraform.tfstate` in plain text. If the state file
is ever lost, `terraform import` recovers it — there are only four resources.
