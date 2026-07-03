# Salesforce CI/CD Demo

A minimal, public **Salesforce DX** sample for branch-based deployments with **GitHub Actions**, **JWT authentication**, and **delta deployments** via [sfdx-git-delta](https://github.com/scolladon/sfdx-git-delta). It is not a full application—only four generic demo Apex classes (with tests) and pipeline definitions you can fork and wire to your own orgs.

**Package name:** `salesforce-cicd-demo` (see `sfdx-project.json`)

> **Full walkthrough:** Step-by-step guide with screenshots in [`blog/implement-salesforce-cicd-github-actions.html`](blog/implement-salesforce-cicd-github-actions.html) (local) or publish from `blog/medium-salesforce-cicd-github-actions.md`.

## What you get

| Piece | Purpose |
|-------|---------|
| `DemoAccountService` / `DemoAccountQuery` | Sample Apex (standard Account fields only) |
| `DemoAccountServiceTest` / `DemoAccountQueryTest` | Tests for pipeline runs |
| `.github/workflows/` | Eight workflows — validate on PR + delta deploy on merge, per environment |
| `manifest/package.xml` | Optional manifest for selective CLI retrieve/deploy |
| `ruleset.xml` | Optional PMD ruleset (not used in default workflows) |

No LWC, Flows, or custom objects—only what is needed to demonstrate CI/CD.

## Promotion model

```
feature branch ──PR──► develop (Dev) ──► test (Test) ──► uat (UAT) ──► main (Production)
                         validate          deploy          deploy         validate + quick deploy
```

| Branch | Trigger | Workflow | Action | Tests |
|--------|---------|----------|--------|-------|
| `develop` | PR | `validate-pr-to-develop.yml` | Validate deploy | `RunLocalTests` |
| `develop` | Push/merge | `deploy-on-merge-develop.yml` | Delta deploy | `RunLocalTests` |
| `test` | PR | `validate-pr-to-test.yml` | Validate deploy | `RunLocalTests` |
| `test` | Push/merge | `deploy-on-merge-test.yml` | Delta deploy | `RunAllTestsInOrg` |
| `uat` | PR | `validate-pr-to-uat.yml` | Validate deploy | `RunLocalTests` |
| `uat` | Push/merge | `deploy-on-merge-uat.yml` | Delta deploy | `RunAllTestsInOrg` |
| `main` | PR | `validate-pr-to-main.yml` | Validate deploy | `RunLocalTests` |
| `main` | Push/merge | `deploy-on-merge-main.yml` | Validate + quick deploy | `RunAllTestsInOrg` |

**Delta baseline:** PR workflows diff against the merge-base with the target branch. Deploy workflows use `github.event.before` (not `HEAD~1`) so merge commits produce the correct delta.

## Security (public repo)

Never commit credentials, auth URLs, JWT keys, or certificates.

Store values only in [GitHub Actions secrets](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions), scoped to **GitHub Environments** (`develop`, `test`, `uat`, `production`). For `production`, enable **Required reviewers** so deploys need manual approval.

## First-time setup

### 1. Install CLI and fork the project

Install the [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli), then verify:

```bash
npm install -g @salesforce/cli
sf version
sf plugins install sfdx-git-delta
```

Clone or fork [salesforce-cicd-github-actions-demo](https://github.com/replyaslamYahoo/salesforce-cicd-github-actions-demo) and open it in your editor.

### 2. Create promotion branches

After forking, create the long-lived branches the workflows expect (if they do not already exist):

```bash
git checkout -b develop && git push -u origin develop
git checkout -b test && git push -u origin test
git checkout -b uat && git push -u origin uat
# main usually exists by default
```

Work on **feature branches** and open PRs into `develop`, then promote by merging `develop` → `test` → `uat` → `main`.

### 3. Generate your JWT certificate

JWT bearer flow needs a private key and matching certificate before you create the External Client App. Generate one pair per org (or reuse one pair across orgs):

```bash
openssl req -x509 -newkey rsa:2048 -keyout salesforce.key -out salesforce.crt -days 365 -nodes
```

You'll be prompted for certificate details (country, org name, etc.) — any values work. This produces:

- `salesforce.key` — private key. **Never commit this.** Base64-encode for `SF_PRIVATE_KEY`.
- `salesforce.crt` — public certificate. Upload to the External Client App.

### 4. Prepare Salesforce orgs

For each org (Dev, Test, UAT, Production—or sandboxes for demos):

1. Create a dedicated **integration user** with permission to deploy metadata and run tests.
2. In **Setup → External Client App Manager**, create an **External Client App** (not the legacy Connected App):
   - Enable **OAuth**; add scopes `api` and `refresh_token`
   - Enable **JWT Bearer Flow**; upload `salesforce.crt`
   - On **Policies**, set *Permitted Users* to **Admin approved users are pre-authorized** and assign the integration user's profile
3. Note the **Client ID** for GitHub secrets.

**Callback URL:** the form requires one, but JWT bearer flow does not use it. Any valid URL (e.g. `http://localhost:1717/OauthRedirect`) satisfies the form.

**Integration user permissions:** the profile or permission set needs **API Enabled** and edit access to objects the deploy touches (in this demo, Account only). A profile without API access may authenticate but fail on deploy.

**Encode the private key** for GitHub (workflows expect base64):

```bash
# Linux / macOS
base64 -w0 salesforce.key

# PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("salesforce.key"))
```

**Test JWT login locally:**

```bash
sf org login jwt \
  --client-id YOUR_CLIENT_ID \
  --jwt-key-file salesforce.key \
  --username deploy-user@example.com \
  --instance-url https://test.salesforce.com \
  --set-default
```

Use `https://login.salesforce.com` for production, or your org's My Domain URL.

### 5. Configure GitHub Environments and secrets

In GitHub → **Settings → Environments**, create:

- `develop`
- `test`
- `uat`
- `production` — enable **Required reviewers**

For **each** environment, add these **environment secrets** (not repo-level secrets):

| Secret | Description |
|--------|-------------|
| `SF_CLIENT_ID` | External Client App Client ID |
| `SF_PRIVATE_KEY` | Private key (`salesforce.key`), **base64-encoded** |
| `SF_USERNAME` | Integration user username |
| `SF_INSTANCE_URL` | Login URL or My Domain (e.g. `https://test.salesforce.com`) |

**Environment names must match exactly** — each workflow uses `environment: develop` (etc.) in the YAML. If GitHub has `dev` instead of `develop`, the job can be skipped silently.

### 6. Verify the pipeline

```bash
sf project deploy validate --source-dir force-app --test-level RunLocalTests
```

Open a PR to `develop` and confirm **Validate PR to Develop** passes. Merge and confirm **Deploy to Dev Org** runs.

## Local development

```bash
sf org login web --alias demo --set-default
sf project deploy start --source-dir force-app --test-level RunLocalTests
```

Validate without deploying (same idea as PR validation):

```bash
sf project deploy validate --source-dir force-app --test-level RunLocalTests
```

**Scratch org** (optional; needs a [Dev Hub](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_setup_enable_devhub.htm)):

```bash
sf org login web --alias devhub --set-default-dev-hub
sf org create scratch -f config/project-scratch-def.json -a demo-scratch -d 7
sf project deploy start --source-dir force-app --target-org demo-scratch --test-level RunLocalTests
```

## Repository layout

```
.github/workflows/
  validate-pr-to-develop.yml    validate-pr-to-test.yml
  validate-pr-to-uat.yml        validate-pr-to-main.yml
  deploy-on-merge-develop.yml   deploy-on-merge-test.yml
  deploy-on-merge-uat.yml       deploy-on-merge-main.yml
force-app/main/default/classes/
  DemoAccountService.cls / DemoAccountServiceTest.cls
  DemoAccountQuery.cls / DemoAccountQueryTest.cls
manifest/package.xml            optional; API version 66.0
config/project-scratch-def.json
sfdx-project.json
ruleset.xml                     optional PMD ruleset
.gitignore / .forceignore
```

## How CI deploys metadata

Workflows do **not** deploy the full `force-app` tree on every run. They use **sfdx-git-delta** to build a delta `package.xml` from git history:

```bash
sf sgd source delta --from "$BEFORE_SHA" --to HEAD --output-dir delta/ --source-dir force-app
sf project deploy start --manifest delta/package/package.xml --test-level RunLocalTests
```

**Production** validates first, captures a Deploy ID, then promotes with `sf project deploy quick` to avoid running the full test suite twice.

For local full-package deploys or retrieves:

```bash
sf project retrieve start --manifest manifest/package.xml
sf project deploy start --manifest manifest/package.xml --test-level RunLocalTests
```

`manifest/package.xml` must stay in sync with class names under `force-app/`. `<version>` must match `sourceApiVersion` in `sfdx-project.json` (66.0).

## Setup checklist

- [ ] Install Salesforce CLI (`npm install -g @salesforce/cli`) and `sfdx-git-delta`
- [ ] Fork this repo and create/push `develop`, `test`, `uat`, `main` branches
- [ ] Generate JWT key and certificate (`openssl req -x509 ...`)
- [ ] Create External Client Apps and integration users in each org (API-enabled profiles)
- [ ] Add JWT secrets to GitHub Environments (names must match workflow `environment:` values)
- [ ] Configure `production` environment with required reviewers
- [ ] Run local `sf project deploy validate`
- [ ] Open a PR to `develop` and confirm validate passes
- [ ] Merge to `develop` and confirm delta deploy
- [ ] Promote through `test` → `uat` → `main`

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| JWT auth fails in CI | Verify base64 encoding of private key, Client ID, username, instance URL, and that the integration user is pre-authorized on the External Client App |
| Validate job skipped | Check GitHub Environment name matches the workflow (`develop`, not `dev`) and secrets are set on the environment |
| No changes detected — skipping deploy | Expected when the delta is empty; confirm metadata changed between `event.before` and HEAD |
| Validate runs all org tests unexpectedly | `RunLocalTests` / `RunAllTestsInOrg` include other Apex in the org; use clean pipeline orgs |
| Production deploy blocked | A reviewer must approve the `production` environment job in GitHub |

## Limitations

- `RunLocalTests` / `RunAllTestsInOrg` run tests beyond this repo if other Apex exists in the org. Use clean pipeline orgs or adjust test levels for your environment.
- Demo classes use only standard **Account** fields (`Name`, `Description`). No emails, portal users, or custom fields in source.

## References

- [Salesforce DX Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_intro.htm)
- [Salesforce CLI project commands](https://developer.salesforce.com/docs/atlas.en-us.sfdx_cli_reference.meta/sfdx_cli_reference/cli_reference_project_commands_unified.htm)
- [JWT bearer flow](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_auth_jwt_flow.htm)
- [sfdx-git-delta](https://github.com/scolladon/sfdx-git-delta)
- [GitHub Actions documentation](https://docs.github.com/en/actions)
