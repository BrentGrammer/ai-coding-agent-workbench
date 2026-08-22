# ChainDrop npm supply-chain check

Date: 2026-08-05

## Result

ChainDrop is a real and active npm incident. The supplied review is useful, but some numbers and statements need limits.

- StepSecurity reports 444 package names and 2,212 malicious versions. SafeDep reports 444 package names and 2,234 versions. The difference is due in part to versions that npm removed before every researcher recorded them. The claim of 1,300 affected package names is not supported by the current public lists.
- The first known carrier was `keyv@6.0.0`, published at about 09:35 UTC on August 4. The known first-wave carriers used a `preinstall` script, `setup.mjs`, Bun, and an obfuscated `Math_Symbol.js` payload.
- The code and publication history give strong evidence that the attacker used Jared Wray's GitHub or release credentials. No public maintainer statement confirms the first access method. State this as a strong finding, not a confirmed account history.
- Valid provenance did not prove that the package content was safe. The attacker used the real release pipeline.
- The statement that there was no new wave on August 5 cannot be verified. The main reports still called the incident active or developing when checked.
- Download totals describe possible exposure. They do not show the number of infected systems.

The [StepSecurity report](https://www.stepsecurity.io/blog/chaindrop-npm-worm), [Socket report](https://socket.dev/blog/popular-npm-packages-in-the-keyv-and-cacheable-namespaces-compromised-in-active-supply-chain), and [Wiz report](https://www.wiz.io/blog/keyv-and-cacheable-npm-supply-chain-attack) agree on the core behavior. SafeDep explains the [different version counts](https://safedep.io/keyv-npm-supply-chain-compromise/).

## Confirmed first-wave versions

The reports agree on these full payload carriers:

| Package | Malicious version |
| --- | --- |
| `keyv` | `6.0.0` |
| `flat-cache` | `6.1.24` |
| `file-entry-cache` | `11.1.6` |
| `cacheable-request` | `13.0.20` |
| `@cacheable/utils` | `2.5.1` |
| `cacheable` | `2.5.1` |
| `@cacheable/memory` | `2.2.1` |
| `cache-manager` | `7.2.10` |
| `@cacheable/node-cache` | `3.1.2` |
| `ecto` | `5.0.1` |
| `@cacheable/net` | `2.1.1` |

Use the [Wiz CSV](https://raw.githubusercontent.com/wiz-sec-public/wiz-research-iocs/main/reports/keyv-packages.csv) and the [SafeDep list](https://safedep.io/keyv-npm-supply-chain-compromise/#the-affected-packages) for the second wave. The Wiz CSV has 443 package rows. SafeDep and StepSecurity report 444 package names. The missing name in the Wiz CSV is `@nebula.js/cli-serve`.

## Project check

### AWS lockfile

`infra/aws/package-lock.json` has 44 unique installed package names. None match the 443 names in the Wiz CSV. The extra SafeDep name, `@nebula.js/cli-serve`, is also absent. There are no exact malicious package and version matches.

The lockfile has 46 package entries. All external entries use `registry.npmjs.org` and have a SHA-512 integrity value. `npm ls --all` reports a valid installed tree. No installed package manifest declares a `preinstall`, `install`, or `postinstall` script.

This result applies only to the committed lockfile. It does not prove that a developer machine, npm cache, CI runner, or old image is clean.

### Local artifacts

The local `infra/aws/node_modules` tree was last changed on August 2, before the known attack start. The lockfile and generated CDK files were also last changed on August 2.

The local scan found none of these indicators:

- The three known payload SHA-256 hashes
- `setup.mjs`, `Math_Symbol.js`, or `math_init.js`
- `keyv`, `flat-cache`, `file-entry-cache`, `cacheable-request`, `cache-manager`, `cacheable`, or an `@cacheable/*` package
- `gh-token-monitor` files or text
- `.vscode/tasks.json` or `.claude/settings.json`

The tracked `tools/agents/config/claude/settings.json` file is an expected project file. Its only hook runs the tracked secret-file deny tool.

No GitHub Actions workflow or Dockerfile is present. The ignored `cdk.out` and `dist` artifacts have no known indicator and predate the incident.

### Pinned global packages

`infra/aws/ec2/setup-workbench.sh` pins six global root packages:

| Root package | Version | Known ChainDrop name match | Declared dependency check |
| --- | --- | --- | --- |
| `hunkdiff` | `0.17.3` | No | Seven direct dependencies; no name match |
| `@anthropic-ai/claude-code` | `2.1.220` | No | No declared dependencies |
| `@openai/codex` | `0.146.0` | No | No declared dependencies |
| `opencode-ai` | `1.18.11` | No | No declared dependencies |
| `gh-axi` | `0.1.29` | No | `@toon-format/toon` and `axi-sdk-js`; no name match |
| `npm-axi` | `0.1.1` | No | `axi-sdk-js`; no name match |

The [gh-axi package file](https://raw.githubusercontent.com/kunchenguid/gh-axi/main/package.json) and [npm-axi package file](https://raw.githubusercontent.com/SSBrouhard/npm-axi/main/package.json) show their declared dependencies.

The exact root pins are good, but `npm install -g` has no committed lockfile here. npm can select new transitive versions on each run. The script also runs the `opencode-ai` postinstall file by hand. This is a supply-chain execution point even though the root version is pinned.

### Unpinned installs

The project has these higher-risk install forms:

- `infra/aws/ec2/setup-workbench.sh` runs `npx --yes skills@latest` five times.
- `tools/agents/start_herdr.sh` installs `@openai/codex@latest` and `opencode-ai@latest`, then runs the OpenCode postinstall file.
- `tools/agents/start_opencode.sh` installs `opencode-ai@latest` and runs `skills@latest` and `opencode-openai-codex-auth@latest`.
- `tools/agents/start_codex.sh` and `tools/agents/sandbox_bootstrap.sh` run `skills@latest`.
- Other agent launchers install unpinned CLIs. Most of these use `--ignore-scripts`, which blocks this attack's `preinstall` path but does not make the package safe when the CLI starts.

None of these direct package names are on the current ChainDrop list. Their use of `@latest` or an omitted version still allows a new package or transitive version to enter without a code change.

## Project risk findings

### High: Live installs can select unreviewed code

Agent launchers use `@latest`, omitted versions, and `npx ...@latest`. Some launchers run on start or update. This design can select and run new package code without a repository change. `--ignore-scripts` stops the known ChainDrop `preinstall` path, but the launcher runs the installed CLI later.

### High: Global tool installs have no lockfile

The EC2 setup pins six direct package versions, but `npm install -g` can select new transitive versions. It does not use a committed lockfile. It also runs `opencode-ai/postinstall.mjs` by hand.

### High: An update runs the remote main branch as root

The EC2 first-boot flow clones `main` and runs `setup-workbench.sh` as root. The update command resets to `origin/main` and runs the same file with `sudo`. A compromised GitHub account or repository can therefore become root code on the workbench. The flow does not pin or verify a reviewed commit.

### Medium: The npm policy file does not cover the AWS package

The root `.npmrc` sets `save-exact=true` and `ignore-scripts=true`. npm does not load it when it runs in `infra/aws`, because that directory is the npm project root. `infra/aws/README.md` tells users to run `npm install`, not `npm ci --ignore-scripts`.

The current lockfile has no lifecycle scripts, so this is a future exposure, not evidence of current infection.

### Medium: Other downloads are not verified

Setup scripts use remote shell installers and download some binaries without a recorded checksum or signature check. These paths are outside npm, but they have the same maintainer and host compromise risk.

### Medium: No automatic supply-chain gate is present

The repository has no CI workflow that checks exact lockfile entries against malware data, blocks new lifecycle scripts, verifies package signatures, or enforces a minimum release age.

## Other recent npm campaigns

ChainDrop is the main current check. Three related 2026 incidents also have direct technical evidence and a defined affected set:

- The [TanStack maintainer postmortem](https://tanstack.com/blog/npm-supply-chain-compromise-postmortem) records 84 malicious versions across 42 `@tanstack/*` Router and Start packages on May 11. TanStack gave an all-clear on May 15.
- The [Red Hat bulletin RHSB-2026-006](https://access.redhat.com/security/vulnerabilities/RHSB-2026-006) records 32 packages in the `@redhat-cloud-services/*` scope. Red Hat closed the incident on June 17.
- The [Snyk Phantom Gyp incident list](https://security.snyk.io/node-gyp-supply-chain-compromise-june-2026) records 57 packages that use malicious `binding.gyp` files. The main names are in the `autotel*`, `@jagreehal/*`, and `eslint-plugin-executable-stories*` families, plus `@vapi-ai/server-sdk`, `ai-sdk-ollama`, `awaitly`, and `@evolvconsulting/evolv-coder-lite`. This matters because `--ignore-scripts` alone does not stop every native build path.

No affected package name or version from these three verified sets appears in `infra/aws/package-lock.json`, the pinned global roots, or the npm install commands under `tools/agents`.

## Safe incident response order

If any system installed a listed version, use this order:

1. Isolate the system. Do not use it to rotate credentials.
2. From a clean system, inspect and remove the token watcher and other persistence. Reported paths include `~/.local/bin/gh-token-monitor.sh`, `~/.config/gh-token-monitor/`, a user systemd service, a macOS LaunchAgent, `.claude/settings.json`, and `.vscode/tasks.json`.
3. Rotate GitHub, npm, cloud, Vault, Kubernetes, and SSH credentials from the clean system.
4. Rebuild the runner or machine from a trusted image. Remove package caches and derived images.
5. Reinstall pinned clean packages with scripts disabled. Allow only reviewed scripts.
6. Audit GitHub repositories, workflows, releases, tokens, and unexpected repositories used for data theft.

The order matters. Socket and StepSecurity report a watcher that can run an attacker-controlled response when a GitHub token changes. Remove that watcher before rotation.

Useful file hashes from Socket are:

- First-wave `setup.mjs`: `54dc7ea54a1317cca0e890a2770630cf7fa6c97813e0cb9d2caa93012b350668`
- Second-wave `setup.mjs`: `fd3ca4007b225fdf8de7af4345a19179d5efa8c4bb9205f88cda806e5684b1eb`
- Main payload: `9fc2570b7cef51c1b8df116d144d11ff4096357be7d2c4c6367cfc2509cf1bcc`

## Recommended project action

1. Stop automatic npm and skill updates until each exact version or Git commit is reviewed.
2. Replace each npm `@latest` or unpinned install with a reviewed exact version.
3. Put the agent CLI set in a small package manifest with a committed lockfile, or verify each downloaded tarball against a reviewed integrity value before global install.
4. Pin the EC2 setup source to a reviewed commit. Do not run a moving branch as root.
5. Add `infra/aws/.npmrc` with the required install policy. Change setup instructions to `npm ci --ignore-scripts`.
6. Use `--ignore-scripts` by default. Put each required lifecycle script on a short allow list and run it in an isolated build step.
7. Add a minimum package age to reduce exposure to a fast attack. npm supports [`min-release-age`](https://docs.npmjs.com/cli/v12/using-npm/config/#min-release-age).
8. On npm 12, use [`npm approve-scripts`](https://docs.npmjs.com/cli/v12/commands/npm-approve-scripts/) so dependency scripts are blocked until a version-specific approval exists.
9. Add a focused CI check for malware lists, new lifecycle scripts, lockfile integrity, and package signatures.
10. Check the live malicious-package list in addition to `npm audit`. No npm advisory record for this event was found on August 5, so a clean audit result is not incident clearance.
11. Keep provenance checks, but do not use provenance as a malware decision. npm documents [provenance limits](https://docs.npmjs.com/generating-provenance-statements/#provenance-limitations).

## Audit limits

This audit did not inspect developer home directories, npm caches, live EC2 systems, CI runners, or old images. It did not inspect any `.env` file. The npm advisory and signature commands could not reach their registry and Sigstore services from the audit environment. This does not change the exact IOC comparison, and an npm advisory result alone cannot clear this incident.
