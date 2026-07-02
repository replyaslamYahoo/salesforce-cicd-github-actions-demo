# Salesforce CI/CD Demo

A minimal, public **Salesforce DX** sample for branch-based deployments with **GitHub Actions**. It is not a full application—only four generic demo Apex classes (with tests) and pipeline definitions you can fork and wire to your own orgs.

## What you get

| Piece | Purpose |
|-------|---------|
| `DemoAccountService` / `DemoAccountQuery` | Sample Apex (standard Account fields only) |
| `DemoAccountServiceTest` / `DemoAccountQueryTest` | Tests for pipeline runs |
| `.github/workflows/` | Validate on PR; deploy per environment branch |
| `manifest/package.xml` | Optional manifest for CLI retrieve/deploy of the same classes |

No LWC, Flows, or custom objects—only what is needed to demonstrate CI/CD.

## Security (public repo)

Never commit credentials, auth URLs, JWT keys, or certificates.

Store values only in [GitHub Actions secrets](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions). For production, create a GitHub **environment** named `production` with required reviewers so `main` deploys need approval (see `main.yml`).

## Promotion model

```
feature branch ──PR──► develop (Dev) ──► test (Test) ──► uat (UAT) ──► main (Production)
                         validate          deploy          deploy         validate + deploy
```

| Trigger | Workflow | What runs | Tests |
|---------|----------|-----------|-------|
| PR → `develop` | `feature.yml` | `deploy validate` to Dev org | `RunLocalTests` |
| Push `develop` | `develop.yml` | `deploy start` to Dev | `RunLocalTests` |
| Push `test` | `test.yml` | Deploy to Test | `RunAllTestsInOrg` |
| Push `uat` | `uat.yml` | Deploy to UAT | `RunAllTestsInOrg` |
| Push `main` | `main.yml` | Validate, then deploy to Production | `RunAllTestsInOrg` |

After forking, create branches `develop`, `test`, `uat`, and `main` if your process matches this flow.

## First-time setup (fork)

1. Create Salesforce sandboxes (or scratch orgs) for Dev, Test, and UAT, plus a Production org (or prod sandbox for demos).
2. In GitHub → **Settings → Secrets and variables → Actions**, add the secrets listed below.
3. In GitHub → **Settings → Environments**, add `production` and enable **Required reviewers**.
4. Push to `develop` (or open a PR) to confirm Dev auth and deploy.

## Required GitHub secrets

| Secret | Workflows | Notes |
|--------|-----------|-------|
| `SFDX_AUTH_URL_DEV1` | `feature.yml`, `develop.yml` | Sfdx Auth Url from Dev org |
| `SFDX_AUTH_URL_TEST1` | `test.yml` | Test org |
| `SFDX_AUTH_URL_UAT1` | `uat.yml` | UAT org |
| `SF_CLIENT_ID_PROD` | `main.yml` | Connected App consumer key (JWT) |
| `SF_PRIVATE_KEY_PROD` | `main.yml` | Private key, **base64-encoded** |
| `SF_USERNAME_PROD` | `main.yml` | Integration user username |
| `SF_INSTANCE_URL_PROD` | `main.yml` | Login URL or My Domain (e.g. `https://login.salesforce.com`) |

**Sandbox auth URL**

```bash
sf org login web --alias my-sandbox --set-default
sf org display --target-org my-sandbox --verbose
```

Use the **Sfdx Auth Url** line as the secret value. Workflows log in with `sf org login sfdx-url`.

**Production (JWT)**

Use a Connected App with a certificate and an integration user. Encode the private key for `SF_PRIVATE_KEY_PROD`:

```bash
# Linux / macOS
base64 -w0 server.key

# PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("server.key"))
```

`main.yml` decodes that secret before `sf org login jwt`.

## Local development

Install the [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli).

```bash
sf org login web --alias demo --set-default
sf project deploy start --source-dir force-app --test-level RunLocalTests
```

Validate without deploying (same idea as `feature.yml`):

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
.github/workflows/       develop.yml, feature.yml, test.yml, uat.yml, main.yml
force-app/main/default/classes/
  DemoAccountService.cls / DemoAccountServiceTest.cls
  DemoAccountQuery.cls / DemoAccountQueryTest.cls
manifest/package.xml      same four classes; API version 66.0
config/project-scratch-def.json
sfdx-project.json
.gitignore / .forceignore
```

## Manifest

`manifest/package.xml` must stay in sync with class names under `force-app/main/default/classes/`. `<version>` must match `sourceApiVersion` in `sfdx-project.json` (66.0).

CI always deploys the full default package:

```bash
sf project deploy start --source-dir force-app
```

Use the manifest only for selective CLI work:

```bash
sf project retrieve start --manifest manifest/package.xml
sf project deploy start --manifest manifest/package.xml --test-level RunLocalTests
```

## Limitations

- `RunLocalTests` / `RunAllTestsInOrg` run tests beyond this repo if other Apex exists in the org. Use clean pipeline orgs or adjust test levels for your environment.
- Demo classes use only standard **Account** fields (`Name`, `Description`). No emails, portal users, or custom fields in source.
