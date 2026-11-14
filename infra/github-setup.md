# GitHub setup checklist

Snapshot of this lab's GitHub configuration; verify settings in the customer
repository rather than copying identity values.

| Scope | Configured | Needed before enabling code CD |
| --- | --- | --- |
| Repository variable | `APP_NAME` (`lab` here; 1-3 lowercase letters/digits) | Same |
| Repository secrets | None | None for OIDC |
| `Dev` environment | Variables `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`; no secrets | Add `AZURE_RESOURCE_GROUP`, `AZURE_FUNCTION_APP_NAME` |
| `Test` environment | Same three variable names; no secrets | Add target variables and replace copied Dev values with a separate Test identity |

Both environments allow the `main` workflow ref. Dev has no reviewer and permits
administrator bypass. Test requires one reviewer, permits self-review, and
disables administrator bypass. Configure a separate environment-scoped Azure
OIDC federated credential and appropriate Azure role for each real target.

Current branch rules: `main` requires a PR, enforces rules for administrators,
blocks force pushes/deletion, and has **no required checks or approval count**.
It does not require code-owner or last-push approval, stale-review dismissal,
conversation resolution, signed commits, linear history, or restricted push
actors; the branch is not locked.
`develop` and `test` are unprotected; no repository rulesets were returned.
After publishing the workflows, verify and require the always-running
`PR checks` status on all PR target branches. Protect workflow/gate changes
with review or ownership rules. The intended promotion is
`develop` → `test` → `main`.

Both CD workflows are disabled. Before enabling code CD, provision a trusted
Linux self-hosted runner labelled `private-function-deploy`, with Azure CLI,
GitHub CLI, and private DNS/routing to the Function App SCM endpoint. Do not run
untrusted PRs on it. Configure the target resource groups, identities and
permissions; Test code CD would deploy, unlike the infrastructure Test
approval demonstration. See the root README for bootstrap and network limits.
