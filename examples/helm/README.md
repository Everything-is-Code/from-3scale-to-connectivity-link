# Helm Example - App of Apps

Deploy workloads using an Argo CD App of Apps pattern. The root chart renders Argo CD `Application` resources that point at standalone Helm charts under `components/`.

## Quick Start

1. Fork or clone this repository and point `gitops.repoUrl` in `values.yaml` at your Git remote.
2. Enable or disable pieces under `components:` (hello-world, showroom) and `connectivityLink.apps:` (connectivity-link stack).
3. Order **Field Content CI** from RHDP with your repository URL and GitOps path `examples/helm` (or the path you use for this chart).

RHDP injects `deployer.domain` and `deployer.apiUrl`. Optional **LiteMaaS / MaaS** ordering injects `litemaas.apiUrl`, `litemaas.apiKey`, and `litemaas.model` into this chart’s values when enabled.

**ApplicationSet (user GitOps):** The component [`components/applicationsets`](components/applicationsets/) — listed in `values.yaml` as `connectivity-link-applicationsets` — deploys the Argo CD **ApplicationSet** (plus Gitea repo-creds helpers) that discovers user repositories after the Developer Hub Golden Path publishes manifests. It is part of this Helm install, not a separate bootstrap. Keep that app **enabled** for multi-user workshops.

## Architecture

```
examples/helm/
├── Chart.yaml
├── values.yaml
├── templates/
│   ├── applications.yaml              # hello-world, showroom, optional single-operator
│   └── connectivity-link-applications.yaml   # connectivity-link Argo CD apps
└── components/
    ├── applicationsets/               # ApplicationSet: Gitea SCM → per-user Applications
    ├── operator/                      # Optional single OLM subscription (template)
    ├── hello-world/
    ├── showroom/                      # Lab guide (from-3scale-to-connectivity-link)
    ├── connectivity-link-operators/   # OLM operators (RHCL, mesh, Dev Spaces, RHBK, …)
    ├── connectivity-link-namespaces/
    ├── connectivity-link-rhcl-operator/
    ├── connectivity-link-developer-hub/
    ├── connectivity-link-observability/
    ├── connectivity-link-neuralbank-stack/
    └── …                              # see values.yaml → connectivityLink.apps
```
Connectivity-link manifests are **vendored** from [connectivity-link](https://gitlab.com/maximilianoPizarro/connectivity-link): plain YAML directories were rendered with `kubectl kustomize` into `templates/all.yaml` where applicable; the `operators` and `neuralbank-stack` upstream Helm charts were copied as subcharts.

## Configuration

| Area | Purpose |
|------|---------|
| `gitops.repoUrl`, `gitops.revision`, `gitops.basePath` | Git source Argo CD uses for every child `Application` |
| `connectivityLink.apps[]` | Toggle each connectivity-link app, destination namespace, prune, sync-wave |
| `connectivityLink.operators` | `channel`, `version`, `subscriptions` passed to `connectivity-link-operators` |
| `connectivityLink.neuralbank` | Values merged into `connectivity-link-neuralbank-stack`; Keycloak URLs are overridden from `deployer.domain` |
| `litemaas.*` | Single LLM source (RHDP injects `apiKey`). Propagated to OLS, Developer Hub Lightspeed, openshift-mcp-server LiteLLM, ApiShift `ai.*`, and `apishift-secrets` (`gateforge-ai-secret`). Defaults: MaaS RHDP endpoint + `qwen3-14b`. Never commit real API keys. |
| `maas.*` / `lightspeed.*` | Legacy fallbacks if `litemaas.*` is empty |
| `components.showroom` | Showroom content repo, nookbag, terminal (default: from-3scale-to-connectivity-link) |

**ApiShift:** Deployed as a Git-sourced Helm app (`connectivityLink.helmApps` with `path: helm/apishift`) from [Everything-is-Code/apishift](https://github.com/Everything-is-Code/apishift) `@main`, namespace `gateforge`, images `quay.io/maximilianopizarro/gateforge-{frontend,backend}:latest` (retagged from upstream builds; upstream Quay org uses `everythingascode/apishift-*`). Route host kept as `gateforge-gateforge.<domain>`. AI secret: `gateforge-ai-secret` via `ai.existingSecret` (`components/apishift-secrets` from `litemaas.apiKey`).

**Migration Toolkit RHCL:** Git-sourced Helm app (`connectivityLink.helmApps` id `migration-toolkit-rhcl`, enabled) from [maximilianoPizarro/migration-toolkit-rhcl](https://github.com/maximilianoPizarro/migration-toolkit-rhcl) path `helm/migration-toolkit-rhcl` (fork with latest chart/images). Docs: [Everything-is-Code/migration-toolkit-rhcl](https://github.com/Everything-is-Code/migration-toolkit-rhcl). Namespace `migration-toolkit`, route `migration-toolkit.<domain>`, images `quay.io/maximilianopizarro/migration-toolkit-rhcl-{backend,frontend}:v0.1.0`. ConsoleLink: **Migration Toolkit RHCL** (ApplicationMenu → API Management).

**Kuadrant Console (custom-rhcl-console):** Git-sourced Helm app (`connectivityLink.helmApps` id `custom-rhcl-console`) from [maximilianoPizarro/custom-rhcl-console](https://github.com/maximilianoPizarro/custom-rhcl-console) path `helm/custom-rhcl-console` — docs [GitHub Pages](https://maximilianopizarro.github.io/custom-rhcl-console/). Namespace **must** be `custom-rhcl-console`. Registers OpenShift `ConsolePlugin` (sidebar) + optional dns-prober; not a standalone ApplicationMenu link.

**Note:** LiteMaaS-related YAML in `connectivity-link-litemaas` still contains cluster-specific URLs from the upstream snapshot. For a new cluster, adjust `cluster-config` / domain handling in that chart or maintain a fork.

## Testing Locally

```bash
helm lint .
helm template my-release . --set deployer.domain=apps.cluster.example.com
```

## Adding a Component

1. Add a Helm chart under `components/<name>/`.
2. Append an entry to `connectivityLink.apps` in `values.yaml` (or add a dedicated block in `templates/applications.yaml` if it needs special `valuesObject` handling).
