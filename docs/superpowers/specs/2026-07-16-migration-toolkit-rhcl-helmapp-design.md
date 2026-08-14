# Design: Migration Toolkit RHCL as optional Helm App

**Date:** 2026-07-16  
**Status:** Approved  
**Cluster pattern:** `examples/helm` (field-content / Connectivity Link workshop)

## Problem

Noriaki Mushino’s [migration-toolkit-rhcl](https://github.com/nmushino/migration-toolkit-rhcl) GUI (Quarkus + PatternFly) converts 3scale exports to Connectivity Link YAML using this repo’s adapter. The upstream install path is `deploy/install.sh` (S2I + local Maven/npm). The workshop needs a **GitOps-friendly, bash-free** way to deploy it later, without enabling it by default until the chart is contributed back to Mushino’s repo.

## Goals

1. Wire the existing Helm chart at [Everything-is-Code/migration-toolkit-rhcl](https://github.com/Everything-is-Code/migration-toolkit-rhcl) (`helm/migration-toolkit-rhcl`) into App of Apps via `connectivityLink.helmApps`.
2. Keep it **`enabled: false`** so workshop installs are unchanged until explicitly flipped.
3. No bash / S2I in this repo — images from Quay (`quay.io/everythingascode/migration-toolkit-rhcl-{backend,frontend}:v0.1.0`).
4. Document how to enable and how to retarget `repoURL` to `nmushino/migration-toolkit-rhcl` after upstream merge.

## Non-goals

- Vendoring the chart under `examples/helm/components/`
- ConsoleLink / Developer Hub catalog entry (optional follow-up)
- Changing Mushino’s `install.sh` or forking build pipeline here
- Enabling the app on existing workshop clusters by default

## Decisions

| Decision | Choice |
|----------|--------|
| Integration | **helmApps** (same pattern as ApiShift / GateForge) |
| Chart source | Git path on `Everything-is-Code/migration-toolkit-rhcl` → later `nmushino/...` |
| Default | `enabled: false` |
| Namespace | `migration-toolkit` |
| Route host | `migration-toolkit.{{ deployer.domain }}` |
| Image tags | Pin `v0.1.0` (also published as `latest`) |
| Templates | No changes — existing `helmApps` renderer suffices |

## Architecture

```text
field-content (Helm parent)
  └─ Application field-content-helm-migration-toolkit-rhcl   [ONLY if enabled: true]
        source: github.com/Everything-is-Code/migration-toolkit-rhcl
                path: helm/migration-toolkit-rhcl
        destination: migration-toolkit
        → Deployment backend + frontend + PostgreSQL + Route + RBAC
```

## values.yaml sketch

```yaml
connectivityLink:
  helmApps:
    - id: migration-toolkit-rhcl
      enabled: false
      repoURL: "https://github.com/Everything-is-Code/migration-toolkit-rhcl"
      path: helm/migration-toolkit-rhcl
      targetRevision: "main"
      destinationNamespace: migration-toolkit
      syncWave: "9"
      values:
        route:
          enabled: true
          host: "migration-toolkit.{{ .Values.deployer.domain }}"
        backend:
          image:
            repository: quay.io/everythingascode/migration-toolkit-rhcl-backend
            tag: v0.1.0
            pullPolicy: Always
        frontend:
          image:
            repository: quay.io/everythingascode/migration-toolkit-rhcl-frontend
            tag: v0.1.0
            pullPolicy: Always
        postgresql:
          enabled: true
```

## Docs

- `examples/helm/README.md`: short note under Configuration / helmApps.
- Root `README.md`: optional component row pointing at Mushino’s toolkit + enable flag.

## Evolutionary handoff to Mushino

1. Chart already lives in Max’s fork (portable to Mushino via PR).
2. After merge to `nmushino/migration-toolkit-rhcl`, change only `repoURL` in this repo’s `values.yaml`.
3. Flip `enabled: true` when the workshop wants it on by default.

## Verification

```bash
helm template my-release examples/helm --set deployer.domain=apps.example.com \
  | grep -c migration-toolkit-rhcl   # expect 0 when disabled

helm template my-release examples/helm --set deployer.domain=apps.example.com \
  --set connectivityLink.helmApps[N].enabled=true   # index of migration-toolkit-rhcl
  | grep -A20 'helm-migration-toolkit-rhcl'
```

On a live cluster (optional): set `enabled: true`, sync Argo CD, open `https://migration-toolkit.<domain>`.
