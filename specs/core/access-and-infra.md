# Access And Infrastructure Spec

Status: Normative

## Intent

Define the access, Terraform, remote-state, and secret-storage model for the
multi-tenant SaaS repo. This repo follows the same Orun golden-path shape as
`aws-admin`: component-native Terraform declarations, CI behavior compiled by
Orun, environment behavior visible in `intent.yaml`, and cloud access granted
through repo-scoped AWS roles.

## Golden Path References

- `specs/core/orun-golden-path.md` explains how agents should reason about Orun
  repos.
- `../aws-admin/intent.yaml` is the reference for environment shape:
  `dev`, `stage`, `prod`, promotion gates, `parameterDefaults.terraform`, and
  `AWS_REGION`.
- `../aws-admin/stacks/aws-admin-terraform/` is the reference Terraform
  composition contract for `plan-only` and `apply` profiles.
- `../aws-admin/domains/**/component.yaml` and colocated `README.md` files are
  the reference for component descriptor and component documentation style.

## Agent Access

Agents may assume authenticated access to:

- `gh` for GitHub PRs, checks, logs, and repository inspection.
- AWS through the repo-scoped IAM roles created by `aws-admin`.
- `wrangler` only when a task explicitly needs to inspect or verify
  Cloudflare resources.

When access is unclear, task agents must pause or record the blocker instead of
inventing account IDs, role ARNs, project refs, or secret names.

## AWS Admin Boundary

`aws-admin` owns AWS IAM and the shared Terraform state buckets. This repo must
not hand-create IAM users, roles, policies, or S3 state buckets.

The required `aws-admin` component for this repo creates environment-scoped
GitHub OIDC roles for `sourceplane/cirrus`. Those roles must allow:

- Terraform state read/write against the shared S3 state buckets named
  `sourceplane-<env>`.
- AWS Secrets Manager read/write for this repo's secret namespace:
  `<org>/<repo>/<component>/<env>`.
- Read-only identity and policy inspection needed by Terraform plan jobs.

The role names and trust subjects must follow the same pattern as the existing
`aws-admin` GitHub repository components. The multi-tenant SaaS repo consumes
those roles; it does not own their creation.

## CI Secrets And Identity

GitHub Actions must use OIDC-assumed AWS roles rather than committing or logging
long-lived credentials. If a task temporarily relies on existing AWS access
secrets while migrating, it must record the compatibility reason and remove the
fallback in the smallest safe follow-up.

The baseline CI environment needs:

- `ORUN_BACKEND_URL` for Orun remote execution state.
- GitHub token access supplied by Actions.
- AWS role configuration supplied through the Orun Terraform composition or an
  explicit pre-run credential step that is itself encoded in the Orun-planned
  job behavior.
- No provider credential of any kind. Cloudflare tokens are brokered per run
  from the workspace's integration connection; CI holds only `GITHUB_TOKEN`.

Provider-specific credentials and connection facts are resolved from orun
secrets at run time. The historical AWS Secrets Manager path below is
superseded and retained only to explain older reports:

```text
<org>/<repo>/<component>/<env>
```

Example:

```text
sourceplane/cirrus/cloudflare-d1/stage
```

Secret values must never be committed, echoed in logs, or copied into task
reports. Reports may include secret names and non-secret resource IDs.

### Worker Runtime Secrets

Runtime secrets consumed by Cloudflare Workers (OAuth client secrets,
`OAUTH_STATE_SECRET`, billing provider tokens, `SECRET_ENCRYPTION_KEY`, the
GitHub App bundle) follow the same system-of-record rule. They are escrowed
in AWS Secrets Manager as one JSON document per environment:

```text
<org>/<repo>/worker-secrets/<env>
```

mapping `worker → SECRET_NAME → value`. The committed, non-secret
declaration of which secret names each worker requires is
`tooling/secrets-sync/secrets.manifest.json`;
`tooling/secrets-sync/check.mjs` validates escrow payloads and deployed
secret names against it without printing values. Cloudflare worker secrets
are deploy-time copies only — write-only, never the source of truth, and
never read back. Workers must not call AWS Secrets Manager at request time.
The `saas-secrets-sync` epic owns the sync/drift mechanics
(`specs/epics/saas-secrets-sync/`).

Provider **integration configuration** (non-secret but account/environment
specific — OAuth client IDs, Polar product maps, email-from addresses) is
co-located with its paired secret in one document per integration:

```text
<org>/<repo>/integrations/<name>/<env>
```

Non-integration secrets (`SECRET_ENCRYPTION_KEY`, `OAUTH_STATE_SECRET`,
`INTEGRATIONS_STATE_SECRET`) share `<org>/<repo>/platform-secrets/<env>`.
`tooling/secrets-sync/integrations.manifest.json` is the source of truth;
config keys are non-secret and may be logged, secret keys never. Instance
*branding* constants (product name, CLI binary, sales email) stay in the
source `app-config` seam, and orchestration parameters (AWS account, region,
domains) stay in `intent.yaml` — neither belongs in Secrets Manager.

## Terraform State

Terraform state for this repo uses AWS S3, not Cloudflare R2.

All Terraform components must use the same backend contract as `aws-admin`:

- bucket: `<orgName>-<environment>`; for this repo, `sourceplane-dev`,
  `sourceplane-stage`, and `sourceplane-prod`
- key: `<repo>/<component>/terraform.tfstate`
- `workspace_key_prefix = "env"`
- `encrypt = true`
- `use_lockfile = true`
- region supplied from environment or component parameters, defaulting to
  `us-east-1`

The effective state object path is therefore:

```text
env/<environment>/<repo>/<component>/terraform.tfstate
```

The old R2 bootstrap component is deprecated and must be removed from active
repo source by Task 0003.1. That task is source deletion only; it must not
clean up, import, destroy, or otherwise mutate live Cloudflare, R2, or
Terraform state resources.

## Terraform Components

Infrastructure provisioning must be represented as Orun-discovered Terraform
components under `infra/terraform/**`.

Minimum target components:

- `cloudflare-d1` — the environment's D1 database, publishing its id as a
  wiring document;
- `cloudflare-kv` — the api-edge idempotency namespace;
- further Cloudflare infrastructure components that wire Workers, queues, or
  other runtime resources when they become task scope.

Terraform components must follow the `aws-admin` component style:

- `spec.type: terraform`
- `spec.domain` aligned with the repo's intent groups
- typed values under `spec.parameters`
- `terraformDir: terraform`
- pinned `terraformVersion`
- explicit `dependsOn` edges for provider-resource ordering
- `plan-only` by default, with `apply` selected by profile rules on the merge
  trigger
- a colocated `README.md` with metadata, purpose, resources, parameters,
  outputs, usage, dependencies, and operational notes

## Database Ownership

**Cloudflare D1 is the primary relational database for product-owned state**,
and it is the only database this baseline has. There is no second provider to
provision, consent to, or hold a credential for — that is what makes Cirrus
the Cloudflare-only baseline.

The current target decision is:

- One D1 database per environment, created by Terraform
  (`infra/terraform/cloudflare-d1`) through Orun jobs.
- Only `stage` and `prod` are provisioned. `dev` is intentionally
  database-less and must not be added without a decision entry in
  `ai/context/decisions.md`.
- Database names follow `<namespacePrefix><repo>-<env>`, e.g. `cirrus-stage`
  and `cirrus-prod`. Names are unique per Cloudflare account, so the repo slug
  keeps a fork from colliding with the baseline in a shared account.
- Database ids are assigned by Cloudflare at creation and published as a
  non-secret wiring output (`WIRING_CLOUDFLARE_D1`) after apply.

The database infrastructure component must:

- authenticate with the brokered `d1-edit` token (`CLOUDFLARE_D1_TOKEN`), NOT
  the `workers-deploy` token — the deploy credential deliberately cannot reach
  the database;
- publish `d1_database_id` / `d1_database_name` as its wiring document, so
  Worker deploys resolve the binding by id and `db-migrate` finds the database
  it migrates;
- carry `adopt.tf`, importing an existing database at plan time rather than
  colliding with it;
- expose only non-secret outputs in Terraform outputs and reports.

Schema changes are the `db-migrate` component's job: ordered, checksummed
migrations under `packages/db/src/migrations`, planned on pull requests and
applied on merge. Nothing else may mutate the schema — including a human with
`wrangler d1 execute`.

D1 constraints that shape every design decision downstream (see
`ai/context/decisions.md` for the full list): no interactive transactions, no
schemas (bounded contexts are table-name prefixes), and SQLite types
(ISO-8601 text timestamps, JSON as text, booleans as 0/1).

## Orun Execution

All infrastructure plan/apply behavior must run through Orun. Direct
Terraform or Wrangler apply commands in GitHub Actions are prohibited unless
they are emitted by an Orun composition job.

Required validation for infrastructure changes:

```bash
kiox -- orun validate --intent intent.yaml
kiox -- orun plan --intent intent.yaml --view dag
kiox -- orun plan --intent intent.yaml --output plan.json
kiox -- orun run --plan plan.json --dry-run --runner github-actions
```

Use `--changed` when proving PR scoping, and use full plans when validating
environment promotion or cross-component dependency behavior.

## Acceptance Criteria

- `cirrus` uses the Orun runtime pinned in `kiox.yaml`
  (authoritative; `kiox.lock` records the resolved digest) while continuing to
  follow `aws-admin` for Terraform component and backend structure.
- `intent.yaml` uses the `dev`, `stage`, `prod` environment shape and
  Terraform parameter defaults from the AWS-admin pattern.
- Terraform state uses S3 buckets `sourceplane-<env>` and the AWS-admin state
  key pattern.
- AWS-admin-created roles allow the multi-tenant SaaS CI path to read/write its
  Secrets Manager namespace and Terraform state.
- `stage` and `prod` each have their own Terraform-created D1 database, and
  their ids reach Workers only through the published wiring document.
- CI and local `kiox -- orun ...` behavior are verified from rendered plans,
  not inferred from file names.
- Resource creation or permission changes are verified against live provider
  state before merge.
