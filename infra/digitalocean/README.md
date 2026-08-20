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

## Setting up another machine

Install the tools, run `doctl auth init`, and copy
`~/.config/agent-workbench/digitalocean-llm.env` from the first machine.
If the first machine is gone, re-create the secrets instead: a new Spaces
key, destroy token, and Tailscale key from the control panels (delete the
old ones). Nothing is unrecoverable. The account resources already exist,
so skip `terraform apply`; run `terraform import` only if Terraform is
needed again.

## Terraform state

State stays local and gitignored, because Terraform writes resource secrets
(the Spaces keys) into `terraform.tfstate` in plain text. If the state file
is ever lost, `terraform import` recovers it — there are only four resources.

## Setup for Future Reference (new machine)

1. Install the tools: brew install doctl and terraform (see readme links for install)
2. Main API token: create at cloud.digitalocean.com → API → Tokens (full access). Then doctl auth init (paste it) and export DIGITALOCEAN_TOKEN=<thetoken>
3. Admin Spaces Access key: control panel → Spaces Keys → create. Then export SPACES_ACCESS_KEY_ID=<key> SPACES_SECRET_ACCESS_KEY=<secret>
4. Apply Terraform:
   terraform -chdir=infra/digitalocean/terraform init
   terraform -chdir=infra/digitalocean/terraform apply
5. Self-destroy token: control panel → API → Tokens → custom scopes → only droplet delete. This is what the box uses to kill itself.
6. Write ~/.config/agent-workbench/digitalocean-llm.env, chmod 600, six lines:

```shell
 mkdir -p ~/.config/agent-workbench
touch ~/.config/agent-workbench/digitalocean-llm.env
chmod 600 ~/.config/agent-workbench/digitalocean-llm.env
```

```shell
DIGITALOCEAN_LLM_CACHE_BUCKET=agent-workbench-llm-cache
DIGITALOCEAN_SPACES_REGION=nyc3
SPACES_ACCESS_KEY_ID=$(terraform -chdir=infra/digitalocean/terraform output -raw spaces_access_key_id)
SPACES_SECRET_ACCESS_KEY=$(terraform -chdir=infra/digitalocean/terraform output -raw spaces_secret_access_key)
DIGITALOCEAN_LLM_DESTROY_TOKEN=<token from step 5>
TAILSCALE_AUTH_KEY=<same GPU-box key the AWS path uses>
```

     (Note: the two Spaces values here are the bucket-scoped key Terraform created in step 4 — not the admin key from step 3.)

7. First run:
   WORKBENCH_LLM_PROVIDER=digitalocean workbench llm up
   First-ever boot is slow (~30 min: registry pull + cache upload). When done, prompt it once, then:
   WORKBENCH_LLM_PROVIDER=digitalocean workbench llm down
   WORKBENCH_LLM_PROVIDER=digitalocean workbench llm status # must say "off"
   That last check is the one that costs money if it's wrong — confirm the droplet is really gone.

- Tailnet join: a few minutes — cloud-init has to install git, clone the repo, and get through the setup script to the Tailscale step.
- This first-ever boot is the slow one: the cache is empty, so it pulls the 17 GB model from the registry and uploads it to Spaces. The llm up readiness wait gives up warning after ~10
  minutes of no model; on this boot that warning is expected, not a failure. It will tell you to check the log for Cache miss: — that's this case.
  - Check with `ssh root@agent-llm 'sudo tail /var/log/cloud-init-output.log'`
  - look for
  ```shell
  == Done. Serving qwen3.8:27b on http://agent-llm:11435/v1
  Cloud-init v. 26.1-0ubuntu1~22.04.1 finished at Thu, 20 Aug 2026 01:10:08 +0000. Datasource DataSourceConfigDrive [net,ver=2][source=/dev/vdb].  Up 213.54 seconds`
  ```

  - confirm: `curl http://agent-llm:11435/v1/models`
- To watch progress once it's on the tailnet: ssh root@agent-llm 'tail -f /var/log/cloud-init-output.log'
- Every later boot restores from Spaces instead: ~5 minutes.

If the wait times out, just poll with WORKBENCH_LLM_PROVIDER=digitalocean workbench llm status and try a prompt once the log reaches == Warming the model. And remember the test that matters at the end of the
session: llm down, then status must say off.

- check context available: `ssh root@agent-llm 'nvidia-smi --query-gpu=memory.used,memory.total --format=csv && ollama ps'`

### KV Cache Precision

- On DO boxes we can up it to a higher precision since the boxes have more memory than some of the default AWS instances in the G Series.
- More bits = more decimal places = a more exact number. The KV cache is the model's working notes on your conversation — for each token
  it has read, it keeps a batch of numbers so it doesn't have to re-read everything on every reply. f16 writes those notes with 16 bits per number (full detail). q8_0 squeezes each one into 8 bits — half the memory, but every number gets slightly rounded. A short conversation shrugs that off; at 100K+ tokens the model is reasoning over a hundred thousand slightly-rounded notes, and the rounding can start to show as dumber answers. That's the whole trade: memory versus exactness.
- switch cache mid session: `ssh root@agent-llm 'sed -i "s/OLLAMA_KV_CACHE_TYPE=q8_0/OLLAMA_KV_CACHE_TYPE=f16/" /etc/systemd/system/ollama.service.d/override.conf && systemctl daemon-reload && systemctl restart ollama'`
