# Container Debug Toolbox Image

Created: 2026-10-06
Author: info@manuel-vogel.de
Agent: Claude Code
Category: Infrastructure
Status: Final
Research: Quick

## Problem Statement

Debugging workloads in Kubernetes and other container environments means reaching for network, DNS, TLS, and cluster-inspection binaries that production images deliberately omit. Operators need a single, small, trustworthy image they can run as an ephemeral pod or `kubectl debug` target that already contains these tools. The image must itself be low-risk to deploy into a cluster: minimal, hardened, non-root, reproducibly built, always current, and published with a verifiable supply chain.

## Core User Flows

### Flow 1: Debug a cluster from inside it
1. Operator runs `kubectl run toolbox --rm -it --image=ghcr.io/mavogel/toolbox:<version>` (or `kubectl debug ... --image=...`).
2. A shell opens as a non-root user with the debug binaries on `PATH`.
3. Operator uses tools such as `dig`, `curl`, `tcpdump`, `kubectl`, `k9s`, `nmap` to diagnose the issue, then exits and the pod is removed.

### Flow 2: Maintainer ships a change
1. Maintainer commits with a Conventional Commit message; pre-commit hooks (via prek) reject non-conforming messages locally.
2. Change merges to `main`.
3. CI runs semantic-release, which computes the next version, creates a GitHub Release with notes, and publishes a multi-arch image to `ghcr.io/mavogel/toolbox` tagged with the semver (and `latest`).

### Flow 3: Tool versions stay current
1. Renovate opens PRs when a pinned tool version, base image, or GitHub Action has a new release.
2. CI builds the image to validate the update; the maintainer merges.
3. A conventional `fix`/`feat`/`chore(deps)` commit type governs whether the merge triggers a release.

### Flow 4: Consumer follows a floating major
1. Consumer references `ghcr.io/mavogel/toolbox:1` (or the git tag `v1`) to always get the latest compatible 1.x release.
2. Each new 1.x release moves the floating tags forward; exact `X.Y.Z` tags stay immutable for reproducible use.

### Flow 5: Image is verified before publish
1. On every PR and before every release push, CI builds the image and runs the smoke test.
2. For each binary in the tool inventory the test checks it is on `PATH`, is executable, and runs its version (or `--help`) command with exit code 0.
3. Any missing, non-executable, or failing binary fails the pipeline and blocks the merge or release.

## Scope

### In Scope
- Multi-stage `Dockerfile`: builder stages fetch/verify pinned tool binaries; final stage is Alpine with a busybox shell, only the needed runtime packages, and a non-root default user.
- Extended tool set: kubectl, helm, k9s, stern, crictl, etcdctl, grpcurl, jq, yq, curl, openssl, dig/nslookup, netcat, tcpdump, iproute2 (`ip`, `ss`), traceroute, nmap, mtr, iperf3, dive, trivy, vegeta.
- Hardening: pinned versions and digests, checksum/signature verification of downloaded binaries, non-root user, no unnecessary packages/package-manager caches, minimal image size, `.dockerignore`.
- Multi-arch builds: linux/amd64 and linux/arm64.
- Renovate configuration that tracks tool versions in the Dockerfile, base image digests, pre-commit hook revisions, and GitHub Actions.
- `prek` + `pre-commit` configuration enforcing Conventional Commits on `commit-msg`, plus basic hygiene hooks and Dockerfile linting (hadolint).
- semantic-release configuration publishing GitHub Releases (changelog/notes) from `main`.
- GitHub Actions workflows: PR validation (lint, image build, smoke test) and release (semantic-release, multi-arch build and push to `ghcr.io/mavogel/toolbox`, SBOM and provenance attestations, cosign signing).
- Floating major tags on each release: image tags `X`, `X.Y` and `latest` alongside immutable `X.Y.Z`, plus a git tag `vX` moved to the release commit (e.g. `v1`).
- Protected `main`: a GitHub repository ruleset requiring pull requests, passing status checks (lint, build, smoke test), up-to-date branches, linear history, and blocking force-push and deletion; applied via a committed, re-runnable `gh api` script and documented in the README. The release workflow must still be able to create releases and tags under this ruleset.
- Binary smoke test: a script that, for every tool in the inventory, asserts it is on `PATH`, is executable, and its version/help invocation exits 0, run against the built image for each platform it can run on (amd64 natively; arm64 via emulation). The inventory drives the test, so adding a tool without a check fails.
- README documenting usage (`kubectl run` / `kubectl debug`), tool inventory, and contribution/commit conventions.

### Explicitly Out of Scope
- ctop — requires a Docker/containerd socket and does not fit Kubernetes debugging; dive and trivy remain.
- Publishing to registries other than GHCR (e.g. Docker Hub) — only GHCR was requested.
- A Helm chart or Kubernetes manifests for deploying the toolbox — usage is via ad-hoc `kubectl run`/`kubectl debug`.
- Privileged or capability-expanding defaults — the image runs non-root; elevated debugging (e.g. raw capture) is opt-in by the operator at run time.
- Windows or other non-Linux images.

## Technical Context

- **Repository state:** empty beyond `README.md`; remote is `github.com/mavogel/toolbox`; default branch history has a single initial commit.
- **Constraints (user-specified):** Dockerfile must use staged builds; final image based on Alpine with busybox shell; commit hooks run through `prek` using `.pre-commit-config.yaml`-compatible config; releases via semantic-release to GitHub Releases and ghcr.io; automated dependency updates via Renovate.
- **Constraints (platform):** semantic-release needs Conventional Commit messages on `main`; GHCR publishing from GitHub Actions uses `GITHUB_TOKEN` with `packages: write`; tools such as tcpdump/nmap raw modes need extra Linux capabilities granted by the operator at run time.
- **Constraints (protection):** semantic-release must not push commits back to protected `main` (releases and tags only); the ruleset must permit the release workflow to create tags, including moving the floating `vX` tag.
- **Constraints (smoke test):** some tools lack a uniform `--version` (e.g. `ss`, `ip`, busybox applets); each uses its own flag, with `--help` as the fallback.
- **Existing code:** none to reuse.

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Final base image | Alpine + busybox shell | Small, ships a shell and ergonomic for interactive debugging while keeping attack surface low |
| Tool set | Extended (core + nmap, mtr, iperf3, etcdctl, dive, trivy, vegeta) | User choice; ctop dropped (assumption: needs a container-runtime socket, not useful in k8s) |
| Platforms | linux/amd64 + linux/arm64 | Covers Apple-Silicon and Graviton-style nodes |
| Registry | ghcr.io/mavogel/toolbox | Requested; tied to the existing GitHub remote |
| Supply chain | SBOM, provenance, cosign signing | Assumption: in keeping with the "hardened" requirement; low cost within the release workflow |
| Image tags | `X.Y.Z` (immutable) + floating `X`, `X.Y`, `latest`; git tag `vX` floats too | User asked for a floating major; image tags drop the `v` prefix per Docker convention (assumption) |
| Branch protection | Repository ruleset on `main`, applied by script | User requirement; script keeps it reproducible. Applying it needs repo admin rights and is a separate manual step |
| Smoke test | Per-binary PATH + executable + version/help exit 0, inventory-driven | User requirement; blocks merge and release on failure |
| Hook framework | prek reading pre-commit config | Requested; prek is a drop-in, faster pre-commit-compatible runner |
| Release trigger | Push to `main` | Assumption: standard semantic-release flow |
