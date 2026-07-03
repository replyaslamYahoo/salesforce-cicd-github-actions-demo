# How to Implement Salesforce CI/CD with GitHub Actions (Step by Step)

*A working pipeline you can fork today — branch-based promotion across Dev, Test, UAT, and Production, with validate-on-PR and delta deploy-on-merge.*

If you've ever hand-deployed metadata to production on a Friday afternoon and spent the weekend hoping nothing broke, this is for you. This walkthrough builds a real, branch-based CI/CD pipeline for Salesforce using GitHub Actions, the Salesforce CLI, and sfdx-git-delta — with every step backed by an actual screenshot from a working repo, not a theoretical diagram.

**Audience:** Salesforce developers and release managers
**Time:** ~45 minutes
**Demo project:** [salesforce-cicd-github-actions-demo](https://github.com/replyaslamYahoo/salesforce-cicd-github-actions-demo) (package name `salesforce-cicd-demo`)

The repo is deliberately minimal — four generic Apex classes with tests — so you can focus entirely on the pipeline mechanics rather than application logic. Fork it, follow along, and you'll have a working four-environment pipeline by the end.

---

## Overview

Each environment is gated by branch and environment protection rules:

- **Pull requests** run `sf project deploy validate` against the target org
- **Merges** deploy only the delta (changed metadata) using sfdx-git-delta
- **Production** validates first, then uses `sf project deploy quick` for a faster, test-skipping deploy

> **What this demo is (and isn't):** This is a teaching repo for CI/CD patterns, not a production application. It uses standard Account fields only, JWT auth across all environments, and GitHub Environments for approval gates.

---

## Prerequisites

Before forking the project, get these in place:

- **[Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli)** (`sf`) — validates and deploys metadata
- **Four Salesforce orgs** — Dev, Test, UAT, and Production (or sandboxes for a demo run)
- **External Client App + certificate** — for JWT bearer flow CI authentication
- **A GitHub repository** — to host workflows and secrets
- **An integration user per org** — a dedicated deploy user with appropriate permissions

Install the CLI if you don't already have it, then verify:

```
npm install -g @salesforce/cli
sf version
sf plugins install sfdx-git-delta
```

**[IMAGE 1 → 01-prerequisites.png]**
*Terminal showing `sf version` and installed plugins.*

---

## 1. Open the tutorial project

Clone or fork [salesforce-cicd-github-actions-demo](https://github.com/replyaslamYahoo/salesforce-cicd-github-actions-demo) and open it in your editor. The repo contains:

- `force-app/main/default/classes/` — four demo Apex classes (`DemoAccountService`, `DemoAccountQuery`, and tests)
- `.github/workflows/` — eight workflows (validate on PR + deploy on merge, per environment)
- `ruleset.xml` — optional PMD ruleset (not used in the default workflows)
- `manifest/package.xml` — optional manifest for selective CLI retrieve/deploy
- `sfdx-project.json` — Salesforce DX project config (API 66.0)

**[IMAGE 2 → 02-open-project.png]**
*VS Code Explorer showing the salesforce-cicd-demo project structure.*
*Look for: `.github/workflows/` with eight YAML files, and `force-app/main/default/classes/` with the demo Apex.*

Create the four long-lived branches the workflows expect, then push them so GitHub has them:

```
git checkout -b develop && git push -u origin develop
git checkout -b test && git push -u origin test
git checkout -b uat && git push -u origin uat
# main usually already exists as your default branch
```

**[IMAGE 2b → 14-branch-create.png]**
*Terminal showing git checkout -b and push for develop, test, uat branches.*

---

## 2. Understand the branch promotion model

Metadata flows through four long-lived branches, each mapped to a Salesforce org:

```
feature branch ──PR──► develop (Dev) ──► test (Test) ──► uat (UAT) ──► main (Production)
                     validate          deploy          deploy         validate + deploy
```

- **develop** — PR → `validate-pr-to-develop.yml` → Validate deploy → `RunLocalTests`
- **develop** — Push/merge → `deploy-on-merge-develop.yml` → Delta deploy → `RunLocalTests`
- **test** — PR → `validate-pr-to-test.yml` → Validate deploy → `RunLocalTests`
- **test** — Push/merge → `deploy-on-merge-test.yml` → Delta deploy → `RunAllTestsInOrg`
- **uat** — PR → `validate-pr-to-uat.yml` → Validate deploy → `RunLocalTests`
- **uat** — Push/merge → `deploy-on-merge-uat.yml` → Delta deploy → `RunAllTestsInOrg`
- **main** — PR → `validate-pr-to-main.yml` → Validate deploy → `RunLocalTests`
- **main** — Push/merge → `deploy-on-merge-main.yml` → Validate + quick deploy → `RunAllTestsInOrg`

**[IMAGE 3 → 03-branch-model.png]**
*GitHub branches view showing develop, test, uat, and main.*
*Look for: four environment branches — develop, test, uat, and main.*

---

## 3. Generate your JWT certificate

JWT Bearer Flow needs a private key and a matching self-signed certificate before you can create the External Client App. Generate one pair per org (or reuse one pair across orgs if you'd rather manage fewer secrets):

```
openssl req -x509 -newkey rsa:2048 -keyout salesforce.key -out salesforce.crt -days 365 -nodes
```

You'll be prompted for certificate details (country, org name, etc.) — any values work, they're not validated by Salesforce. This produces two files:

- `salesforce.key` — the private key. Never commit this. You'll base64-encode it for `SF_PRIVATE_KEY` later.
- `salesforce.crt` — the public certificate. This is what you upload into the External Client App below.

**[IMAGE 4 → 15-openssl-cert.png]**
*Terminal showing the openssl req command generating salesforce.key and salesforce.crt.*
*Look for: salesforce.key and salesforce.crt listed afterward with ls / dir.*

---

## 4. Configure Salesforce orgs and JWT auth

All workflows authenticate with **JWT bearer flow**. For each org (Dev, Test, UAT, Production), create an **External Client App** (not the legacy Connected App) and wire it to your integration user.

1. In Setup, search for **External Client App Manager** (under Apps → External Client Apps)
2. Create an External Client App — enable OAuth, add scopes `api` and `refresh_token`, enable JWT Bearer Flow, and upload the `salesforce.crt` you just generated
3. Open the app's **Policies** tab — set *Permitted Users* to **Admin approved users are pre-authorized** and assign the integration user's profile (e.g. System Administrator)
4. Store the private key securely — the workflows expect it base64-encoded in GitHub as `SF_PRIVATE_KEY`

> **About the Callback URL field:** the form requires one, but JWT Bearer Flow doesn't actually use it — there's no browser redirect in this flow. Any syntactically valid URL (e.g. `http://localhost:1717/OauthRedirect`) satisfies the form; it isn't called at runtime.

> **Integration user permissions:** whatever profile or permission set you assign needs API Enabled and edit access to any object the deploy touches (in this demo, just Account). A stripped-down profile without API access will authenticate fine but fail on deploy with a permissions error that doesn't obviously point back to the profile.

**[IMAGE 4a → 06-external-app-manager.png]**
*Salesforce Setup search showing External Client App Manager.*
*Look for: Setup search → External Client App Manager under External Client Apps.*

**[IMAGE 4b → 06-external-app-create.png]**
*Create External Client App with OAuth, JWT Bearer Flow, and certificate.*
*Look for: OAuth enabled, callback URL set, scopes `api` and `refresh_token`, "Enable JWT Bearer Flow" checked, and certificate uploaded. After creation, note the Client ID for `SF_CLIENT_ID`.*

**[IMAGE 4c → 06-external-app-policies.png]**
*External Client App policies with admin approved users.*
*Look for: Permitted Users = "Admin approved users are pre-authorized" and the deploy user's profile selected.*

Encode the private key for GitHub secrets:

```
# PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("salesforce.key"))

# Linux / macOS
base64 -w0 salesforce.key
```

Test JWT login locally (use the External Client App Client ID as `--client-id`):

```
sf org login jwt \
  --client-id YOUR_CLIENT_ID \
  --jwt-key-file salesforce.key \
  --username deploy-user@example.com \
  --instance-url https://test.salesforce.com \
  --set-default
```

> **Never commit credentials.** Don't commit auth URLs, JWT keys, certificates, or passwords. Store values only in [GitHub Actions secrets](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions).

---

## 5. Configure GitHub secrets and environments

In GitHub → **Settings → Secrets and variables → Actions**, create secrets for each GitHub Environment. Each environment (`develop`, `test`, `uat`, `production`) needs its own set:

- `SF_CLIENT_ID` — External Client App Client ID
- `SF_PRIVATE_KEY` — private key, base64-encoded
- `SF_USERNAME` — integration user username
- `SF_INSTANCE_URL` — login URL or My Domain (e.g. `https://test.salesforce.com`)

**[IMAGE 5 → 04-github-secrets.png]**
*GitHub Actions secrets for Salesforce JWT auth.*

In GitHub → **Settings → Environments**, create `develop`, `test`, `uat`, and `production`. For `production`, enable **Required reviewers** so production deploys need manual approval.

**[IMAGE 6 → 05-github-environments.png]**
*GitHub Environments with production approval gate.*
*Look for: the production environment with required reviewers enabled.*

> **Environment names must match exactly:** each workflow references its environment by name (`environment: develop` in the YAML). If the GitHub Environment is named `dev` instead of `develop`, or the casing doesn't match, the job silently skips rather than erroring — this is the single most common "why didn't my validate job run" cause.

---

## 6. Validate locally before CI

Before opening a PR, confirm auth and validation work from your machine:

```
sf project deploy validate \
  --source-dir force-app \
  --test-level RunLocalTests
```

**[IMAGE 7 → 07-local-validate.png]**
*Terminal showing a successful `sf project deploy validate` run.*

---

## 7. PR validation workflows

When you open a PR to `develop`, `test`, `uat`, or `main`, the validate job authenticates via JWT, generates a delta package, and runs `sf project deploy validate`.

For PRs, the delta baseline is the merge-base with the target branch — the most accurate diff for review:

```
BASE_SHA=$(git merge-base HEAD origin/${{ github.base_ref }})

sf sgd source delta \
  --from "$BASE_SHA" \
  --to HEAD \
  --output-dir delta/ \
  --source-dir force-app
```

**[IMAGE 8 → 08-pr-validation-workflow.png]**
*validate-pr-to-develop.yml workflow with the validate job.*
*Look for: a single validate job with JWT auth, delta package generation, and `sf project deploy validate`.*

**[IMAGE 9 → 09-pr-checks-running.png]**
*GitHub PR checks showing the validate step passing.*

---

## 8. Delta deploy on merge

When a PR is merged (push to the environment branch), the deploy workflow uses `github.event.before` as the delta baseline — correct for merge commits, unlike `HEAD~1`.

```
BEFORE_SHA="${{ github.event.before }}"

sf sgd source delta \
  --from "$BEFORE_SHA" \
  --to HEAD \
  --output-dir delta/ \
  --source-dir force-app

sf project deploy start \
  --manifest delta/package/package.xml \
  --test-level RunLocalTests
```

Destructive changes (metadata deletions) are deployed separately with `NoTestRun` when present.

**[IMAGE 10 → 10-delta-package-output.png]**
*Workflow log showing the generated package.xml from sfdx-git-delta.*
*Look for: the logged output of package.xml and destructiveChanges.xml before deploy.*

**[IMAGE 11 → 11-merge-deploy-workflow.png]**
*deploy-on-merge-develop.yml workflow YAML.*

---

## 9. Production quick deploy

Production uses a two-step pattern to avoid running the full test suite twice:

1. `sf project deploy validate` with `RunAllTestsInOrg` — captures a Deploy ID
2. `sf project deploy quick --job-id` — promotes the validated deployment without re-running tests

```
DEPLOY_ID=$(sf project deploy validate \
  --manifest delta/package/package.xml \
  --test-level RunAllTestsInOrg \
  --json | jq -r '.result.id')

sf project deploy quick --job-id $DEPLOY_ID
```

**[IMAGE 12 → 12-production-quick-deploy.png]**
*Production workflow validate and quick deploy steps.*
*Look for: the validate step capturing a Deploy ID, then the quick deploy step using that ID.*

---

## Setup checklist

- [ ] Install Salesforce CLI (`npm install -g @salesforce/cli`) and `sfdx-git-delta`
- [ ] Fork [salesforce-cicd-github-actions-demo](https://github.com/replyaslamYahoo/salesforce-cicd-github-actions-demo) and create/push `develop`, `test`, `uat`, `main` branches
- [ ] Generate a JWT private key and self-signed certificate (`openssl req -x509 ...`)
- [ ] Create External Client Apps and integration users in each org, with API-enabled profiles
- [ ] Add JWT secrets to GitHub Environments (names must exactly match workflow `environment:` values)
- [ ] Configure the `production` environment with required reviewers
- [ ] Run local `sf project deploy validate`
- [ ] Open a PR to `develop` and confirm validate passes
- [ ] Merge to `develop` and confirm delta deploy
- [ ] Promote through `test` → `uat` → `main`

---

## Troubleshooting

**JWT auth fails in CI** — Verify base64 encoding of the private key, Client ID, username, and instance URL, and confirm the integration user is pre-authorized on the External Client App.

**"No changes detected — skipping deploy"** — Expected when the delta is empty. Confirm you pushed metadata changes between `event.before` and HEAD.

**Validate runs all org tests unexpectedly** — `RunLocalTests` / `RunAllTestsInOrg` include any other Apex tests present in the org, not just this repo's. Use clean pipeline orgs.

**Merge commit breaks the delta** — The workflows use `github.event.before`, not `HEAD~1`, specifically to handle merge commits correctly.

**Validate job skipped** — Check the GitHub Environment name matches the workflow (`develop`, not `dev`) and that secrets are set.

**Production deploy blocked** — Check the GitHub Environment approval — a reviewer must approve the production environment job.

---

## Official references

- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_intro.htm)
- [Salesforce CLI project commands](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/cli_reference_project_commands_unified.htm)
- [sfdx-git-delta plugin](https://github.com/scolladon/sfdx-git-delta)
- [GitHub Actions documentation](https://docs.github.com/en/actions)
- [JWT bearer flow](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_auth_jwt_flow.htm)

**[IMAGE 13 → 13-github-actions-run.png]**
*Successful end-to-end GitHub Actions run across the CI/CD pipeline — the hero shot for the close of the article.*

---

*All screenshots captured on Windows with Visual Studio Code, Salesforce CLI, and GitHub Actions, from the [salesforce-cicd-github-actions-demo](https://github.com/replyaslamYahoo/salesforce-cicd-github-actions-demo) repo.*
