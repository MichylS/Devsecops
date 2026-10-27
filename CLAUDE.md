# CLAUDE.md

This file gives Claude Code (claude.ai/code) guidance for working in this repository.

## What this repository is

A **notes-and-snippets repo** for a school DevSecOps assignment (the "DSO-bouwstraat"), graded against `Assessment-Rubric-v4.pdf`. It is **not** a buildable application and has no build, lint or test commands. Files are copied from here and applied by hand on a single Ubuntu VM (`ms@k3`, IP `10.24.20.224`) running **k3s**.

Most content is in **Dutch**: workflow step names, commit messages and notes. Keep new workflow step names and user-facing strings in Dutch to match.

The actual demo application (an `index.html` website plus `.gitea/workflows/*.yaml`) lives in a **separate repo**, `~/dso-demo-app` on the VM, which is hosted in the self-hosted Gitea. The workflow files here are working copies of the ones in that repo.

## Target architecture (as built)

Single-node k3s cluster, with Traefik as the ingress controller. Hostnames use `sslip.io` wildcard DNS on `10.24.20.224`:

| Namespace    | What runs there | Hostname |
|--------------|-----------------|----------|
| `gitea`      | Gitea (service `gitea-http:3000`) with Actions enabled | `gitea.10.24.20.224.sslip.io` |
| `demo`       | `demo-website` Deployment that serves `index.html` from ConfigMap `demo-website-html` (service port 80) | `demo.10.24.20.224.sslip.io` |
| `ci`         | Gitea Actions runners: `gitea-runner` (Docker-in-Docker, label `ubuntu-latest`) and `deploy-runner` (label `deployment`) | — |
| `monitoring` | Helm `kube-prometheus-stack` (release `monitoring`, Alertmanager disabled, 3-day retention) and Helm `prometheus-blackbox-exporter` (release `blackbox`) | `grafana.10.24.20.224.sslip.io` |

### CI/CD flow
1. **CI** (`ci.yml` / `ci-metrtivy.yml`): runs on push to `main` and on PRs. A `html-check` job greps `index.html` for expected content and version strings. A `security-scan` job runs Trivy (`secret,vuln`, fails on HIGH/CRITICAL). `ci-metrtivy.yml` is the variant that is actually used. It runs Trivy through `docker run aquasec/trivy:0.69.3` because the `trivy-action` did not work on the runner.
2. **CD** (`deploy.yml` here is outdated; the live version is `.gitea/workflows/deploy.yaml` in `dso-demo-app`): started manually with `workflow_dispatch`, which serves as the manual approval gate. It runs on `runs-on: deployment`. It builds a kubeconfig from Gitea secrets `K8S_TOKEN` and `K8S_CA_CERT` against `https://10.24.20.224:6443`, regenerates ConfigMap `demo-website-html` from `index.html`, and runs `kubectl rollout restart deployment/demo-website`. It then waits for Ready and checks the live site with curl. CI and deploy are **not** linked: no image or artifact is built, and deploy does not require a green CI run.
3. **Least privilege:** Role `demo-deployer` in namespace `demo` grants get/patch/update on ConfigMap `demo-website-html`, get/patch on `deployment/demo-website`, and list on deployments. RoleBindings bind it to ServiceAccounts **`demo/deploy-runner`** and `demo/demo-deployer`. They do **not** bind it to `ci/deploy-runner`, which the runner pod runs as and which has no rights. Deploy access therefore comes only from the `K8S_TOKEN` secret.
4. **Monitoring:** Grafana dashboards from kube-prometheus-stack. Blackbox Exporter probes the demo site through an extra scrape config (`Scrapeconfig-blackbox.yml`), which is stored as Secret `blackbox-additional-config` and wired into Prometheus `additionalScrapeConfigs`.

### Migration to Argo CD (in progress, 2026-10-27)
The plan is in `argocd-stappenplan.md`. `dso-demo-app/` is a local copy of the new files for the app repo: Dockerfile, `k8s/`, `argocd/application.yaml` and the new `ci.yaml`.

Done so far:
- Argo CD (Helm chart `argo-cd` 10.11.6) is installed in `argocd`, reachable at `argocd.10.24.20.224.sslip.io`, with metrics exposed through a ServiceMonitor.
- The `gitea-runner` DinD allows the HTTP registry (ConfigMap `docker-daemon`).
- Application `demo-website` uses manual sync, so a Sync click is the approval step.

Target flow: the CI builds an image, scans it with Trivy, pushes it to the Gitea registry, and commits the new tag into `k8s/deployment.yaml`. `paths-ignore: k8s/**` stops that commit from triggering CI again. A manual Sync in Argo CD then deploys it.

The first Sync was done on 2026-10-27. The website now runs from image `dso-demo-app:<sha>`.
- Gotcha: Argo CD's client-side apply did **not** remove the old ConfigMap volume (`website-html`), because that field had never been in Argo CD's last-applied config. It was removed by hand with a JSON patch. Argo CD still showed "Synced" because it only compares the fields that are in the manifest.

Security pipeline (live since 2026-10-27, first fully green release `b2d13df`; `deploy.yaml` has been removed from the app repo):
- **Phase 1, parallel:** html-check, Semgrep SAST (`p/default`, `p/dockerfile`, `p/kubernetes`), Trivy fs (secrets and vulns), Trivy config.
- **Phase 2:** `build` (plus Trivy image scan), then `sbom` (Syft, SPDX artifact) and `dast` (ZAP baseline against the image running read-only as UID 101; `.zap/rules.tsv` ignores 10049).
- **Phase 3:** `release` pushes the image and commits the tag.
- Jobs share images through the single runner's DinD daemon, so this breaks if more runners are added.
- Actions are pinned to commit SHAs, because Semgrep flags mutable tags.
- **Never use `docker run -v "$PWD:..."` in workflows.** The job container and the DinD daemon do not share a filesystem, so the scanner gets an EMPTY dir and passes. Until 2026-10-27 every repo scan did this ("0 files"). Use `scripts/scan.sh <image> <args> /src` (`docker create` + `docker cp`) instead. Socket-based scans (`trivy image`, Syft) are not affected.
- The app is hardened: `nginx-unprivileged` on port **8080**, security headers in `nginx/default.conf`, CSS moved to `style.css` so the CSP needs no `unsafe-inline`, the pod runs read-only and non-root with `/tmp` as emptyDir, and the Service targets 8080.

The old push deploy was removed from the cluster on 2026-10-27: deploy-runner, RBAC, ServiceAccounts and ConfigMap `demo-website-html`. In this notes repo, `deploy.yml`, `nieuwe depleyment` and `demo-deployer role` are now historical only. The old push deploy (`deploy.yaml`, deploy-runner, `K8S_TOKEN`, RBAC) used to stay in place until the new chain is verified (phase 6 of the plan).

### Live state (snapshot 2026-10-27)
- **VM:** 4 vCPU, 15 GiB RAM and a 29 GB disk that is 70% full. Software versions: k3s v1.36.5, Gitea 1.27.0 (Helm chart 12.7.0, with PostgreSQL and a 3-node Valkey cluster) and kube-prometheus-stack 92.10.1.
- **Gitea `app.ini`:** `[actions] ENABLED=true`, `[packages] ENABLED=true` (so the container registry is available) and `[metrics] ENABLED=false`, which means Prometheus has no build or Gitea metrics.
- **Website:** version 2.1 is live. Its last rollout was on 2026-10-18.
- **Uptime Kuma** is not installed, and neither are Alertmanager, Argo CD or anything else from the "target state" in `k3s-bouwstraat.md`.

## File guide

| File | Purpose |
|------|---------|
| `k3s-bouwstraat.md` | The original design or plan document: architecture, phases, security controls, assessment demo script and proposed repo layout. This is the target state, and much of it (Argo CD, Semgrep, ZAP, container registry) is not built yet. |
| `Nieuwide-pipeline.md` | A raw chronological log of the build: commands run, errors hit and fixes. This is the best source for *how* things were actually set up. |
| `txt.md` | A partial copy of the runner and Secret troubleshooting part of the build log. |
| `ci.yml`, `ci-metrtivy.yml`, `deploy.yml`, `runnnertest.yml` | Gitea Actions workflows, which go into `.gitea/workflows/` in `dso-demo-app`. |
| `nieuwe depleyment` | A shell heredoc that writes the newer `deploy.yaml`. |
| `gitea-runner-k3s.yaml` | Namespace `ci` and the privileged DinD runner Deployment, which uses hostPath mounts of `/var/lib/act_runner` and `/etc/act_runner/config.yaml`. |
| `gitea runnerservce.yml` | A systemd unit for a VM-native runner. This approach was abandoned in favour of the in-cluster DinD runner. |
| `*-ingres*.yml`, `webserve-ingress.yml` | Traefik Ingresses for Gitea, Grafana and the demo site. |
| `demo-deployer role` | The RBAC Role for deployments. |
| `Scrapeconfig-blackbox.yml` | The Prometheus scrape job for the Blackbox Exporter. |

## Gotchas
- Several `.yml` files are **not pure YAML**. They contain shell wrappers or a trailing `EOF` because they were pasted from `sudo tee ... <<'EOF'` commands, for example `monitoring-ingres.yml`, `gitea-runner-k3s.yaml` and `Scrapeconfig-blackbox.yml`. Strip these before running `kubectl apply -f`.
- Some filenames have spaces or no extension (`demo-deployer role`, `nieuwe depleyment`, `gitea runnerservce.yml`). Quote them in shell commands.
- On the VM, cluster commands run as `sudo k3s kubectl ...`, and Helm runs as `sudo helm ... --kubeconfig /etc/rancher/k3s/k3s.yaml`.
- DinD runner pods used to hang on every slow start, not only after a reboot. `s6-notifyoncheck` gives up while dockerd is still starting, so `s6-svwait` waits forever, `gitea-runner daemon` never starts, and Gitea reports "No matching online runner". Two fixes are in place, as ConfigMaps in `ci` (see `gitea-runner-k3s.yaml`):
  - ConfigMap `runner-start` replaces `/etc/s6/gitea-runner/run` with a script that waits on `docker info` without a limit.
  - A `livenessProbe` running `pgrep -f "[g]itea-runner daemon"` restarts the pod if the runner still does not start.
- `K8S_TOKEN` comes from Secret `demo/deploy-runner-token` (type `service-account-token`, does not expire). Test RBAC with `--as=system:serviceaccount:demo:deploy-runner`, **not** with `sudo k3s kubectl --token=...`: the admin client certificate in `k3s.yaml` takes precedence over the token, so every check passes.
- The CI `html-check` greps for exact strings such as `<h1>Mijn DevSecOps-demo</h1>` and `Versie: X.Y`. When the demo bumps the version in `index.html`, update the grep in CI as well.
- **The build logs (`Nieuwide-pipeline.md`) contain plaintext credentials**: a Gitea/Grafana admin password and a runner registration token. Never copy them into new files, workflows or commits. Use Kubernetes Secrets or Gitea Actions secrets instead, as the cluster setup already does for `deploy-runner-token`.
