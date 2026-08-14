# Migration Toolkit RHCL HelmApp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional, disabled-by-default Argo CD `helmApps` entry for Mushino’s migration toolkit chart.

**Architecture:** Reuse existing `connectivityLink.helmApps` renderer; point at Git-sourced chart `helm/migration-toolkit-rhcl` on Everything-is-Code’s fork; pin Quay images `v0.1.0`.


**Tech Stack:** Helm parent chart (`examples/helm`), OpenShift GitOps / Argo CD Application CR.

## Global Constraints

- `enabled: false` by default
- No bash / S2I in this repo
- Do not vendor the chart under `components/`
- Do not commit secrets or cluster tokens

---

## Task 1: Add helmApps entry

**Files:** `examples/helm/values.yaml`

- [x] Append `migration-toolkit-rhcl` block after `apishift` in `connectivityLink.helmApps` per design sketch
- [x] Verify `helm template` does **not** emit the Application when disabled
- [x] Verify with values overlay (`enabled: true`) that Application renders with correct repoURL/path/namespace

## Task 2: Document

**Files:** `examples/helm/README.md`, `README.md`

- [x] Note helmApps entry + enable flag + evolutionary `repoURL` swap to nmushino
- [x] Add optional component mention in root README components table if present
