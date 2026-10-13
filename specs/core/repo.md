# Monorepo Spec

Status: Normative

## Intent

This repository starts as a Cloudflare-first monorepo for a reusable multi-tenant SaaS starter bootstrap. It should let implementation move quickly across identity, organizations, projects, membership, billing, audit, usage, notifications, webhooks, admin/support, and optional product extensions while preserving clean seams for later extraction into separate repos and deployments.

## Canonical Repo Shape

```text
intent.yaml                Orun intent — composition sources, discovery roots, env lanes
kiox.yaml                  Orun runtime pin, aligned with aws-admin
kiox.lock                  Resolved Kiox provider lock
/.orun                     Generated local Orun state, plans, locks, and runs; ignored by git
/.github
  /workflows
    ci.yml                 Portable Orun plan/run workflow for PRs and main

/apps
  /api-edge                Public HTTP entry Worker
    component.yaml         Component descriptor (type: cloudflare-worker-turbo)
  /web-console-next        Next.js console (Workers + Static Assets)
    component.yaml         Component descriptor (type: cloudflare-workers-assets-turbo)
  /identity-worker
    component.yaml
  /policy-worker
    component.yaml
  /membership-worker
    component.yaml
  /projects-worker
    component.yaml
  /notifications-worker
    component.yaml
  /webhooks-worker
    component.yaml
  /admin-worker
    component.yaml
  /resources-worker
    component.yaml         Optional starter extension for project-scoped resources
  /config-worker
    component.yaml
  /events-worker
    component.yaml
  /runtime-worker
    component.yaml         Optional starter extension for long-running resource workflows
  /metering-worker
    component.yaml
  /billing-worker
    component.yaml

/packages
  /contracts               Shared API, tenancy, event, starter, resource, and manifest types
    component.yaml         Component descriptor (type: turbo-package)
  /sdk                     Public TypeScript SDK
    component.yaml
  /cli                     Public CLI package
    component.yaml
  /ui                      Shared UI components and generated form helpers
    component.yaml
  /shared                  Generic helpers only: errors, logging, ids, tracing
    component.yaml
  /testing                 Test utilities, fixtures, contract assertions
    component.yaml

/tests
  /components
    /contracts-tests
      component.yaml       Test suite descriptor (type: turbo-test)
    /api-edge-tests
      component.yaml
    /identity-worker-tests
      component.yaml
    /web-console-next-tests
      component.yaml

/tooling
  /eslint
  /tsconfig
  /scripts

/infra
  /terraform
    /cloudflare-d1         D1 platform database per environment
    /cloudflare-kv         api-edge idempotency namespace
    /cloudflare-domain     Zone adoption and console custom domain
  /cloudflare              Wrangler configs, environments, bindings
  /ci                      CI templates and deployment notes

/specs
  ...this spec pack...
```

Execution contracts are not vendored in this tree. They are consumed from the
published catalog `oci://ghcr.io/sourceplane/stack-tectonic`, pinned to an
explicit version in `intent.yaml`.

## Repo Rules

### Workspace and toolchain

- Use `pnpm` workspaces for package management.
- Use `turbo` or an equivalent task graph runner for build, test, typecheck, lint, and deploy pipelines inside components.
- Use `orun` as the only CI orchestration layer for validate, plan, test, verify, and deploy flows. Root scripts may wrap `kiox -- orun ...`, but CI gates must not bypass Orun with ad hoc shell steps.
- Use TypeScript across Workers, SDK, CLI, and shared packages for V1 velocity.
- Each deployable Worker keeps its own `wrangler.jsonc` and deployment pipeline.

### Deployment model

- The public entry point is `apps/api-edge`.
- Internal bounded contexts are separate Workers where service bindings add value.
- The web UI is a separate app and must talk to the public API, not internal Worker bindings.
- Starter-domain asynchronous work uses Cloudflare Queues and Workers behind the owning bounded context.
- Long-running product-resource orchestration may live in `apps/runtime-worker` using Cloudflare Workflows by default; Durable Objects may be used for locks and strongly consistent coordination.

### State ownership

- Each bounded context owns its own persistence.
- The primary relational store is Cloudflare D1, bound directly into each Worker as `PLATFORM_DB`.
- One D1 database per environment hosts every bounded context. SQLite has no schemas, so each context owns a table-name namespace (`identity_*`, `membership_*`, …) and its own migrations, extractable without rewriting clients.
- No Worker may query another domain's tables or schemas directly.
- Shared caches in KV must be derived, disposable copies of source-of-truth data.
- Every project-scoped table, cache key, event, and query must carry `org_id + project_id`; never rely on `project_id` alone.

### Internal communication

- Prefer Cloudflare service bindings for internal Worker-to-Worker communication.
- Prefer RPC-style service bindings for internal command/query boundaries.
- HTTP fetch between Workers is allowed only when mirroring a public contract is intentional.
- Background work uses Cloudflare Queues and/or Workflows, never fire-and-forget calls without delivery tracking.

### Shared package rules

- `packages/contracts` may contain shared types, schema validators, and contract tests.
- `packages/shared` may contain only generic utilities with no domain knowledge.
- Domain logic must not live in `packages/shared`.
- UI packages must not import internal Worker code.

### Test component rules

- Every CI-gated test suite is modeled as a first-class Orun component under `tests/components/`.
- `packages/testing` holds shared fixtures, harnesses, and helpers; it is not the CI gate by itself.
- Deployable, package, and infra components must declare `dependsOn` edges to the test components that gate them.
- The starter test composition should begin as a `turbo-test` contract in the `stack-tectonic` catalog so unit, contract, integration, and smoke suites can run through Orun with repo-specific inputs.
- A component that cannot name its required test component dependency is not ready to merge.

## Platform Resource Mapping

Use platform primitives deliberately:

- Workers: HTTP ingress and internal domain services
- Service bindings: internal synchronous calls
- D1: source-of-truth relational state for bounded contexts, bound per Worker
- KV: read-heavy cache and idempotency records
- R2: artifacts, manifest bundles, export files, dead-letter archives
- Queues: asynchronous delivery and fanout steps
- Workflows: durable multistep orchestration
- Durable Objects: per-resource locking, coordination, and strongly consistent local state where needed
- Secrets Store and Worker secrets: platform credentials and envelope-encryption keys
- Workers Analytics Engine: usage telemetry and operational analytics

## Primary Database Operating Model

Cloudflare D1 is the primary operational database for product-owned relational state, including identity, membership, projects, config metadata, canonical events, audit indexes, usage rollups, billing state, notifications, webhooks, support actions, and optional resource/runtime metadata.

- Workers reach D1 through the `PLATFORM_DB` binding. There is no connection string to leak: the binding IS the credential, and it never appears in domain logic.
- Terraform provisions the database per environment (`infra/terraform/cloudflare-d1`). The live environments are `stage` and `prod`; `dev` is database-less by design.
- `stage` and `prod` each get their own database, never a shared one.
- The database id reaches Workers only through the published wiring document (`WIRING_CLOUDFLARE_D1`), resolved at deploy time; ids are never committed.
- Local database verification may use temporary credentials only when the task explicitly allows it. Temporary credentials must never be committed, logged in full, or copied into source files.
- Repository adapters own SQL and its dialect. Domain services receive typed repositories, not platform database clients. **D1 has no interactive transaction**: `executor.transaction(...)` runs statements in order without rollback, so an invariant that must hold atomically has to be expressible as one statement (`RETURNING`, `ON CONFLICT`) or carry a compensating path.
- Each bounded context owns its schema or table namespace and migration history. Cross-context foreign keys are prohibited; use opaque IDs, service calls, and published events instead.
- Every tenant-scoped table must include `org_id` directly or have an auditable path to `org_id` through a table owned by the same bounded context.
- Domain mutations and outbox/event inserts that describe the same state change are written together, in order. They do NOT commit atomically — D1 cannot — so the event insert goes last and a partial write is a real, reviewable outcome rather than an impossible one.
- Identity is Cirrus-owned and lives in the identity component. No managed auth service is a source of truth here.

## Operational Access And Resource Verification

Agents may assume authenticated access to `gh`, to AWS through the
`aws-admin`-managed repo roles, and to `wrangler` when a
task explicitly needs provider inspection.

- AWS IAM roles and state buckets are owned by `aws-admin`.
- This repo consumes the `sourceplane/cirrus` GitHub OIDC roles and
  must not create IAM roles directly.
- Terraform state uses the shared `sourceplane-<env>` S3 buckets and native S3
  locking, following the `aws-admin` backend contract.
- Secrets are stored in AWS Secrets Manager, not in committed files or
  task/report bodies.
- Any task that creates or updates Cloudflare, AWS IAM, S3, or
  Secrets Manager resources must verify the resource exists after creation and
  record non-secret observed state in the implementer or verifier report.
- Verifiers must not rely only on successful command exit codes. They must
  inspect provider state directly when a task claims a live resource or
  permission change.

## Extraction Model

The monorepo is successful only if each bounded context can later move without changing public contracts.

A component is considered extraction-ready when:

- its persistence is owned only by that component,
- its internal consumers reach it only through contracts or service bindings,
- it has its own deployment config,
- it has no domain cross-imports,
- its public and event contracts already live in `packages/contracts`.

When a component outgrows Cloudflare-native storage or queueing:

- keep the public and internal contract stable,
- move its owned tables or replace the repository adapter,
- optionally front the external service with the same Worker contract,
- keep database connectivity only at the adapter layer.

## Composition and CI Model

This repo uses [orun](https://orun-api.sourceplane.ai) for composition-driven
CI and deployment. The working model is the Orun golden path captured in
`specs/core/orun-golden-path.md`, with `aws-admin` as the reference implementation
for Terraform, S3 backend, and environment structure.

- **The composition stack** is owned by `sourceplane/stack-tectonic` and consumed
  as a pinned OCI artifact. It is not vendored in this repo; composition changes
  are made, verified and released there, then adopted here by bumping the pinned
  version in `intent.yaml`.
- **`intent.yaml`** records discovery roots, composition sources and bindings,
  trigger bindings, and `dev` -> `stage` -> `prod` environment promotion. It
  uses `parameterDefaults.terraform` and `env.AWS_REGION` like `aws-admin`.
- **`.orun/`** contains generated local Orun plans, locks, and run state. It is
  ignored by git; `kiox.lock` is the committed runtime/provider lock.
- **`component.yaml`** in each app, package, infra module, and test suite
  describes the composition type, environment subscriptions, typed parameters,
  labels, and dependencies. No component is wired into the CI workflow directly.
- **`kiox.yaml`** pins the Orun runtime version and should match the current
  `aws-admin` pin.

Composition types used:

| Type                              | Used by                                           |
| --------------------------------- | ------------------------------------------------- |
| `cloudflare-worker-turbo`         | All Workers in `apps/` except `web-console-next`  |
| `cloudflare-workers-assets-turbo` | `apps/web-console-next` (Next.js + Static Assets) |
| `turbo-package`                   | Shared packages in `packages/`                    |
| `turbo-test`                      | Test suites in `tests/components/`                |
| `terraform`                       | Optional repo-owned infra components in `infra/`  |

The immediate operations tasks are to align the local Orun runtime and
Stack Tectonic contracts with `aws-admin`, delete deprecated R2/core Terraform
component source, add the missing AWS-admin IAM role component for this repo,
establish S3 backend usage with the shared `sourceplane-<env>` buckets, and
then add fresh database infrastructure as a Terraform component.

The base commands stay portable between local execution and GitHub Actions:

- `kiox -- orun validate --intent intent.yaml`
- `kiox -- orun plan --changed --intent intent.yaml --output plan.json`
- `kiox -- orun run --plan plan.json --job <job-id>`

GitHub Actions may add matrix-selected `--job`, `--runner github-actions`, and
remote-state flags, but it must not swap to a different task runner or a
different job graph.

The CI workflow (`ci.yml`) compiles one Orun plan on every PR and push to main, uploads the plan artifact, and fans out `orun run` jobs per selected component or test component. Deployment lanes are encoded in `intent.yaml` environments — there is no separate hand-maintained deploy graph.

Adding a new app, package, infra module, or test suite requires only a colocated `component.yaml`. The workflow does not need to change.

If a composition change is needed, it happens in `sourceplane/stack-tectonic`,
not here:

1. change the schema/profile/job contract and README together in that repo,
2. add or update the matching smoke fixture there when one exists,
3. let its verify workflow gate the change, then tag a release — which publishes
   the new OCI version,
4. bump the pinned `ref:` in this repo's `intent.yaml`,
5. run local `orun validate`, `plan`, and `run --dry-run` against the new pin,
6. then merge the consuming component change.

## CI And Quality Gates

Every change must pass the gates enforced by the matched Orun component graph:

- lint
- typecheck
- unit tests
- contract tests
- integration tests for the changed component
- downstream smoke tests required by changed dependencies
- local `kiox -- orun validate --intent intent.yaml`
- local `kiox -- orun plan --changed`
- local `kiox -- orun run --plan plan.json --dry-run --runner github-actions`
- GitHub Actions `kiox -- orun run --plan plan.json --job <job-id> --runner github-actions --remote-state`

All test execution that can block merge or release must happen through Orun jobs owned by `tests/components/*`. Standalone `pnpm test` jobs in CI are allowed only when they are invoked by a test component composition, not as a second orchestration path beside Orun.

Changes that affect `packages/contracts`, `specs/`, or shared auth, tenancy, project, billing, audit, resource, or webhook flows require downstream smoke tests for every impacted component.

If `orun plan --changed` produces no component jobs, the matching `orun run --changed` result should be recorded as a no-op instead of skipped silently.
