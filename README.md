# Azure private networking lab

A small Bicep lab with a private Azure Key Vault plus Log Analytics,
workspace-based Application Insights, and an Azure Container Registry with
public access disabled. No application workload, VPN, or virtual machine is
included yet.

**Infrastructure CD is paused.** A manual CD workflow run cannot deploy
because both deployment-stage jobs are disabled. The Test job is an approval
demonstration only; no Test or Prod deployment is configured.

## How the Bicep works

1. `infra/main.bicepparam` reads `LAB_APP_NAME` and `INFRA_ENVIRONMENT` at compile
   time. CI passes repository variable `APP_NAME=lab` and validates both `dev`
   and `test` through the validation script.
   `eastus` was selected after registering `Microsoft.App` and observing
   Container Apps managed environment usage of 0 against a limit of 50 there.
   Quota headroom does not guarantee physical capacity or deployment success;
   verify quota, capacity, and policy again before deployment. The
   `10.40.0.0/16` VNet and `10.40.1.0/24` subnet are examples; check address
   overlap before any future deployment.
2. `infra/main.bicep` is the resource-group-scoped entry point. Target the
   independently created `rg-lab-dev-eus` resource group for this lab.
   The template does not create or modify the resource group.
3. `infra/modules/network.bicep` creates the VNet and private-endpoint subnet.
   Keeping this separate lets another component use the same network later.
4. `infra/modules/key-vault.bicep` creates the vault and its private connectivity.
   Key Vault is a managed service, **not a resource deployed inside a subnet**.
   Its private endpoint has a network interface with a private subnet IP.
5. The private DNS zone, `privatelink.vaultcore.azure.net`, is linked to the VNet.
   The endpoint's DNS zone group manages its DNS record; no hardcoded endpoint
   IP or manually maintained A record is needed.
6. Public network access is disabled. Clients still use
   `https://<vault-name>.vault.azure.net`; within the linked VNet, DNS resolves
   that name through Private Link to the private endpoint.
7. Azure RBAC controls secret access separately from networking. The templates
   deliberately do not assign roles or create credentials.

The root also composes three service modules:

| Module | Responsibility |
| --- | --- |
| `log-analytics.bicep` | Usage-billed workspace with 30-day retention |
| `application-insights.bicep` | Workspace-based monitoring linked to that workspace |
| `container-registry.bicep` | Premium registry with admin credentials disabled |

They reuse the root's application, environment, location, and tags, so
`main.bicepparam` needs no new parameters. Existing CI compiles these modules
through `main.bicep`; no workflow or test-script changes are needed.

The resource group, VNet and vault names include application, environment, and
the region label `eus` for East US. The VNet uses the full 13-character
deterministic suffix; the vault uses nine characters for Dev and eight for Test
in `kv-<app>-<env>-eus-<suffix>` to stay within its 24-character limit. The
suffix is derived from the resource group ID and environment to reduce global
vault-name collisions, but availability is not guaranteed. The lab restricts
`location` to `eastus` so it cannot disagree with the region label.
Resources are tagged with application, project, and environment.
Changing labels or resource group changes resource identities; it does not rename existing
resources, and can leave previously deployed resources behind.
The DNS zone uses Azure's required service name, not a custom naming pattern.
The new names follow `law-<app>-<env>-eus-<suffix>` and
`appi-<app>-<env>-eus-<suffix>`. The registry uses
`cr<app><env>eus<suffix>` without hyphens to meet ACR's alphanumeric naming rule.
All three retain the full deterministic suffix; global registry-name
availability is not guaranteed.

The vault module owns this lab's service-specific DNS zone. When adding another
service, give its private DNS zone one clear owner too. If adding a second vault
to the same resource group, first extract the shared Key Vault DNS zone/link
instead of letting two module instances manage the same zone.

## Monitoring and registry access is deferred

Log Analytics and Application Insights disable public ingestion and public
queries. Application Insights stores its telemetry in the lab's Log Analytics
workspace. This does not instrument an application or configure diagnostic
settings.

ACR uses the Premium SKU and disables public access and trusted-service network
bypass. Premium supports a future private endpoint and carries an ongoing
cost if deployed. No new private endpoint, private DNS, or Azure
Monitor Private Link Scope (AMPLS) is created for these three resources.
Disabling public access is **not** the same as providing a working private
connection: monitoring ingestion/query and registry image push/pull are not
ready to use until their private connectivity is deliberately designed.
Management-plane operations and RBAC are separate from these data-plane
network settings.

The existing Key Vault private endpoint and DNS configuration are unchanged.
The new services are not attached to that endpoint.

## How to access a private vault

You need **all three**: a network route to its private IP, correct DNS resolution,
and an identity with an appropriate Key Vault data role.

| Option | What is needed | Suitable use |
| --- | --- | --- |
| Small VM in the VNet | A separate client subnet, Azure CLI, and secure access such as Bastion | Straightforward first networking exercise; VM and Bastion have costs |
| Laptop over point-to-site VPN | VPN gateway, routes, and DNS forwarding through Azure DNS Private Resolver or a DNS forwarder | Use your local CLI or browser |
| VNet-connected Cloud Shell | An explicitly configured VNet-integrated Cloud Shell environment | Browser-based CLI; ordinary Cloud Shell is not in this VNet |

None of these clients or gateways is provisioned by this lab. DNS links alone
do not connect a laptop to the VNet, and VNet peering alone does not link DNS
zones to every peered VNet.

After a future deployment, have an authorized administrator grant your test
identity **Key Vault Secrets User** to read secret values, or **Key Vault Secrets
Officer** to create and manage lab secrets, scoped to this vault. A management
role such as Contributor does not automatically grant secret access.

From the connected client, use these checks (replace the placeholder):

```shell
nslookup <vault-name>.vault.azure.net
az keyvault secret list --vault-name <vault-name> --output table
```

The DNS answer should contain the endpoint's private IP. Listing secret metadata
checks connectivity and authorization without printing secret values; an empty
list is normal for a new vault. The portal's secret screens also need this
private path from your browser. Viewing the resource's configuration through
Azure Resource Manager is different from accessing its secrets.

Public DNS may still resolve the vault name outside your VNet. That does not
mean public access is enabled. GitHub-hosted CI runners also cannot access this
private endpoint merely because they can authenticate to Azure.

## How the YAML works

1. Branch from `develop` for feature changes, then promote by PR from `develop`
   to `test` and from `test` to `main` (Prod). The `develop` and `test` branches
   are currently local only; publish them before configuring PRs or running
   Actions. `main` has no deployment configured.
2. `.github/workflows/ci-pr.yml` runs on every PR targeting those branches.
   `scripts/detect-infra-bicep-changes.sh` checks the changes against the PR base,
   including additions, deletions, and renames. Only changes under `infra/`
   ending in `.bicep` or `.bicepparam` select infrastructure validation.
3. If selected, the PR workflow calls
   `.github/workflows/ci-infra-reusable.yml`. It checks out the PR revision
   with read-only repository permissions and passes `dev` and `test`, along
   with repository variable `APP_NAME`, to the Bash validation script.
4. The script compiles the entry point and parameter file, including referenced
   modules. Generated ARM JSON is temporary. Validation needs no Azure login
   and does no what-if, deployment, or secret access.
5. The always-running `PR checks` job runs the mock shell tests under
   `tests/infra/` and uses `scripts/check-pr-results.sh` to require successful
   change detection and any selected validation. A failing test fails the gate.
   A documentation-only PR skips Bicep validation but still runs these tests
   and reports the gate.
   Script-only and workflow-only PRs also skip Bicep validation; changes to
   those files require review even when the gate passes.
6. `.github/workflows/ci-infra.yml` runs on pushes to `develop`, `test`, or
   `main` only when Bicep or parameter files under `infra/` change. It calls
   the same reusable validation. Documentation-only, script-only, and
   workflow-only pushes do not trigger it.
7. Infrastructure CD is currently paused: `.github/workflows/cd-infra.yml`
   accepts only manual dispatch and both jobs are disabled. Its comments show
   how an authorized maintainer can restore the preserved `workflow_run`
   trigger and guards after reviewing the targets.

### If infrastructure CD is restored

The preserved router is designed to select successful same-repository push CI
runs from `develop` for Dev or `test` for the Test demonstration. Failed CI,
PRs, and other branches cannot deploy. Both routes call
`.github/workflows/cd-infra-reusable.yml`; there is no `main` deployment.

GitHub loads a `workflow_run` router and reusable workflow from the default
branch (`main`), so these files must first reach `main` before restored CD can run.
This bootstrap requirement matters for the initial `develop` → `test` → `main`
promotion: that first promotion cannot exercise this CD from its feature branch.
For the same reason, GitHub evaluates environment branch restrictions against
`main`, not against the upstream CI branch. Both GitHub environments allow
`main`; the router and reusable workflow explicitly check the upstream branch,
repository, event, result, and revision. Those code checks are not equivalent to
an environment-enforced restriction on the upstream branch. Protect changes to
the default branch and these workflows accordingly.

The Dev job would check out the exact CI commit, bind to the `Dev` GitHub environment,
and authenticate with OIDC. `scripts/deploy-infra.sh` compiles the template
and parameters once, previews resource/change summaries with what-if, and
applies the same compiled files incrementally to `rg-lab-dev-eus`. CD re-reads
`APP_NAME` and validates it; if the repository variable changed after CI, CD may
use a different value. It freezes the value for both what-if and apply. What-if
requires deployment-equivalent permissions.

The Test job would bind to `Test` **after validation** and wait for its required
reviewer. After approval it prints a demonstration message; it has no OIDC
permission, Azure login, what-if, or deployment. The copied Test identity
variables are not used. Approval is not review of an Azure what-if, and a
successful demonstration does not establish Test deployment readiness.

**Restoring CD can make a qualifying merge deploy Dev automatically.** The
current `Dev` environment has no required reviewers: what-if must succeed, but
nobody approves its result before apply. A successful rerun for the current
`develop` revision could deploy again. Manual dispatch while CD is paused does
not deploy.

When restored, CD checks that the validated revision is still the `develop` head before
what-if and again before apply. A stale revision fails instead of deploying,
but a branch update can still race with these checks. Deployments to the Dev
resource group are serialized without cancelling an active run. Up to 100 runs
can wait; additional runs are cancelled when the queue is full. Queue order is
based on when jobs begin waiting, not necessarily when they were dispatched,
so no dispatch order is guaranteed. This does not lock out external operators.
If a later non-infrastructure commit makes CI stale, a new Bicep-changing push
to `develop` is needed to trigger CI and CD; rerunning the stale CI does not
bypass the check. Workflow-only and script-only pushes do not trigger push CI
or restored CD, although their PRs still run the gate.

The YAML names follow the existing `ci-infra.yml` convention: `cd-infra.yml`
contains the paused CI-run router and `cd-infra-reusable.yml` contains the shared
deployment-stage workflow. The router defines each branch, environment and
resource group explicitly; the reusable workflow checks the mapping again.
The deployment script deliberately permits only `dev:develop`, so enabling
Test or Prod requires an intentional code change.

Run the same check locally with Azure CLI and Bash installed (Git Bash on Windows):

```shell
bash scripts/validate-infra-bicep.sh dev lab
bash scripts/validate-infra-bicep.sh test lab
```

The script uses a pinned Bicep compiler; its first run may download it. When
compiling the parameter file directly, set `INFRA_ENVIRONMENT=dev` and
`LAB_APP_NAME=lab` first. The application label must be 1-3 lowercase ASCII
letters or digits; the script rejects a missing or invalid value. Direct Bicep
compilation enforces its length, but does not check the character restriction.
The CI validation script checks the resource-group-scoped template without
deploying it; CD is currently disabled.
Compilation checks Bicep syntax, types, and parameter compatibility, not Azure
Policy, name availability, permissions, routing, or whether deployment succeeds.

The `tests/infra/` shell tests run in the PR gate on GitHub runners. They test
change detection, gate decisions, and deployment safeguards using mocks; they
do not contact Azure or deploy resources. Each test step logs its elapsed time.

**Required check:** A PR gate reports `PR checks` even when no infrastructure
validation is needed. Require that final gate, not a path-filtered workflow or
conditional job: a skipped workflow's required check can remain pending. The
gate must fail if change detection fails or an applicable validation fails,
is cancelled, or unexpectedly skips.

The gate and branch configuration are not yet published. `main` requires a
pull request but currently has no required status checks; `develop` and `test`
exist only locally. After publishing the workflows and branches, run a PR to
confirm the actual check name, then configure it as required on each target
branch. Until then, GitHub does **not** enforce this gate.

For a future application, add detection for its actual source, test, and
shared-configuration paths to `ci-pr.yml`, then call its own reusable CI
workflow when selected. Add that job to the gate's `needs`, pass its selection
and result to `scripts/check-pr-results.sh`, and update the script to reject
failed or unexpectedly skipped selected checks. Extend `tests/infra/pr-gate.test.sh`
for selected, unselected, and failed cases. Code CI/CD is not automatically
discovered: adding a workflow alone does not make its result required. Keep
application deployment separate from this infrastructure workflow.

The PR workflow and its scripts are themselves read from the PR revision.
Protect changes to them with appropriate review or ownership rules; a required
check alone does not protect its own implementation.

## Environments and future deployment

The repository Actions variable `APP_NAME` is set to `lab`. If setting up a
new copy of the repository, create this nonsecret repository variable explicitly.
CI fails rather than falling back when it is missing or invalid; for pull
requests from forks, verify the variable is available to the workflow run.

The GitHub repository environment **Dev** is restricted to deployments from
the default workflow ref `main` and has no required reviewers. It contains the
`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID` environment
variables; no client secret is used. A federated credential allows this
repository's `Dev` environment to authenticate as the Azure identity. An
authorized administrator created `rg-lab-dev-eus` and granted this identity
Contributor at that resource-group scope. This does not grant Key Vault data
access. The existing GitHub setting allowing administrators to bypass
environment protection rules remains enabled.

The GitHub environment **Test** allows the default workflow ref `main`, requires approval from
`michaeldeongreen`, and disables administrator bypass. Self-approval is allowed
because this lab specifies only one reviewer; this is not independent review.
Test currently contains copies of the three Dev variables, but its demonstration
does not use them. The Dev identity has no Test federated credential.

To turn Test into a real deployment later, first arrange a separate Test resource
group, identity, Test-scoped federation and least-privilege role assignment;
replace the copied variables with Test's own values. Deliberately enable a Test
branch/environment mapping in the reusable workflow and deployment script,
review its Bicep parameters and what-if, and retain the desired approval policy.
For Prod, follow the explicit Dev/Test caller and environment mappings, add
approved Prod Bicep parameters and naming, a dedicated identity, federation,
resource group and protection rules, and intentionally enable the mapping in
the reusable workflow and script. `main` currently has no Prod CD path.
Do not assume the Test demonstration or copied Dev credentials implement either
environment.

When restored, Dev CD uses the subscription variable and the existing `rg-lab-dev-eus`
resource group with the identity's resource-group-scoped Contributor role.
An authorized administrator owns any further role assignments.
Confirm the target subscription and ownership before deploying; this template
does not manage the group's tags. Do not put credentials in Bicep or the
parameter file.

## Lab cleanup tradeoff

Soft delete is enabled with seven-day retention. **Purge protection is disabled
intentionally for this disposable tutorial**, so an authorized operator can
purge a deleted vault without waiting. This is not the recommended production
setting: enable purge protection for real workloads.

After a future deployment, delete only the dedicated lab resource group when
finished. The vault remains soft-deleted; its name cannot be reused until it is
purged or retention expires. Purging permanently destroys its contents and needs
separate permission such as Key Vault Purge Operator. No cleanup or purge is
performed automatically. Subscription policy may require purge protection and
reject this lab configuration; do not bypass that policy.

Private endpoints and private DNS can incur charges even when idle.

## References

- [Key Vault Private Link](https://learn.microsoft.com/azure/key-vault/general/private-link-service)
- [Private endpoint DNS](https://learn.microsoft.com/azure/private-link/private-endpoint-dns)
- [Key Vault soft delete and purge protection](https://learn.microsoft.com/azure/key-vault/general/soft-delete-overview)
- [Key Vault RBAC](https://learn.microsoft.com/azure/key-vault/general/rbac-guide)
- [Azure Monitor private connectivity](https://learn.microsoft.com/azure/azure-monitor/fundamentals/private-link-configure)
- [ACR private endpoints and Premium SKU](https://learn.microsoft.com/azure/container-registry/container-registry-private-endpoints)
- [ACR trusted-service network bypass](https://learn.microsoft.com/azure/container-registry/allow-access-trusted-services)
