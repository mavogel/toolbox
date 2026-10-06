# Container Debug Toolbox Implementation Plan

Created: 2026-10-06
Author: info@manuel-vogel.de
Agent: Claude Code
Status: PENDING
Approved: Yes
Iterations: 0
Worktree: No
Type: Feature

## Summary

**Goal:** A maintainer can merge Conventional-Commit PRs into a protected `main` and get a smoke-tested, signed, multi-arch Alpine debug image at `ghcr.io/mavogel/toolbox` (immutable `X.Y.Z` plus floating `X.Y`, `X`, `latest`, git tag `vX`), with Renovate keeping every pinned tool current. Requirements: `docs/prd/2026-10-06-container-debug-toolbox.md`.

## Out of Scope

- Pinning individual apk package versions — Alpine drops superseded package versions from its mirrors, which would break rebuilds; freshness comes from the Renovate-pinned base digest instead (see Task 2).
- Making the GHCR package or the repository public — the repo is currently private; visibility is the owner's decision. The README documents `imagePullSecrets` for private pulls.
- Renovate automerge — not requested; every update goes through a PR and the required checks.
- Cryptographic signature verification of upstream tool downloads — downloads are verified against the upstream-published SHA-256 checksum files from the same release.
- Committing or pushing from the agent — git writes and remote setup are the user's action (Task 10).

## Approach

**Chosen:** One multi-stage `Dockerfile`: per-tool Alpine builder stages download pinned, checksum-verified release binaries (Renovate-annotated `ARG`s); the final stage is the same pinned Alpine, adds runtime packages via apk, copies the binaries into `/usr/local/bin`, strips setuid bits and apk-tools, and runs as a numeric non-root user. A reusable `ci.yml` (lint, PR title, per-arch build plus inventory-driven smoke test, Trivy) gates both PRs and releases; `release.yml` calls it, then runs semantic-release, then pushes and signs the image and moves the floating tags.
**Why:** Prebuilt upstream binaries keep builds fast and the image small. Checksums fetched from the upstream release prove integrity rather than authenticity, but let Renovate bump a version with a one-line diff and no hash maintenance.

## Global Constraints

- Platforms: `linux/amd64`, `linux/arm64`
- Image: `ghcr.io/mavogel/toolbox`
- Runtime user: numeric `USER 10001:10001`, home `/home/toolbox`, default `CMD ["/bin/sh"]`
- Downloaded tool binaries live in `/usr/local/bin`; nothing else is placed there
- Every pinned version is an `ARG <TOOL>_VERSION=` line with `# renovate: datasource=<datasource> depName=<dep>` on the line directly above
- Base image referenced as `alpine:<minor>@sha256:<digest>`, identical in every stage
- Git tag format `v${version}`; image tags `X.Y.Z`, `X.Y`, `X`, `latest` (no `v` prefix); floating git tag `vX`
- Required status check names: `lint`, `pr-title`, `build-test (linux/amd64)`, `build-test (linux/arm64)`
- Commit messages and PR titles: Conventional Commits

## Context for Implementer

Tool inventory, by install source:

- **apk (Alpine main/community):** `ca-certificates`, `curl`, `openssl`, `jq`, `bind-tools` (dig/nslookup/host), `netcat-openbsd` (nc), `tcpdump`, `iproute2` (ip, ss), `nmap`, `mtr`, `iperf3`. `traceroute` comes from the busybox applet.
- **Upstream release binaries:**
  - kubectl: dl.k8s.io, `.sha256` file
  - helm: get.helm.sh, `.sha256sum` file
  - k9s: `checksums.sha256`
  - stern: `checksums.txt`
  - crictl (kubernetes-sigs/cri-tools): `.sha256` file
  - etcdctl (etcd-io/etcd): `SHA256SUMS`
  - grpcurl (fullstorydev): `checksums.txt`
  - yq (mikefarah): `checksums` plus `checksums_hashes_order`
  - dive (wagoodman): `checksums.txt`
  - trivy (aquasecurity): `checksums.txt`
  - vegeta (tsenart): `checksums.txt`
  - Confirm each asset name and checksum format against the current upstream release page; the formats differ per project.

Elevated debugging (tcpdump capture, raw-socket nmap) needs the operator to run the container as root with `NET_RAW`/`NET_ADMIN`, e.g. `kubectl debug --profile=netadmin` or a pod `securityContext`. The image must not grant capabilities itself: no file caps, no setuid. The repo is private and its remote has no branches yet. GitHub rulesets on a private personal repo require GitHub Pro, so Task 11 must report the API error verbatim.

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Rulesets unavailable on private repo without GitHub Pro | Medium | `main` stays unprotected | the `gh api` call fails with GitHub's error, which is reported as a blocked item; README states the requirement |
| A tool binary is not executable under arm64 emulation, or the wrong arch asset is fetched | Medium | Broken arm64 image ships | `build-test (linux/arm64)` runs the full smoke test under QEMU and is a required check, and also runs before publish in `release.yml` |
| Upstream CVE blocks every PR via Trivy | Medium | Merges blocked by issues outside our control | Trivy fails only on `CRITICAL` with `--ignore-unfixed`; `.trivyignore` documents accepted exceptions |
| Floating tags move before the image exists | Low | `:1` / `v1` point at a missing or old image | Floating git tag `vX` is moved only after the image push and signing succeed, in the same job |

## Progress Tracking

- [x] Task 1: Commit hooks with prek (Conventional Commits + hygiene)
- [x] Task 2: Multi-stage hardened Dockerfile
- [x] Task 3: Inventory-driven binary smoke test
- [x] Task 4: Renovate configuration
- [x] Task 5: semantic-release configuration
- [x] Task 6: Reusable CI workflow
- [x] Task 7: Release workflow (GitHub Release + GHCR + floating tags)
- [x] Task 8: Drop the protection script (user-agreed)
- [x] Task 9: README documentation
- [ ] Task 10: Push and install Renovate (user)
- [ ] Task 11: Verify remote setup and first release

## Implementation Tasks

### Task 1: Commit hooks with prek

**Objective:** Add a pre-commit-compatible hook config that prek runs locally and in CI. It rejects non-Conventional commit messages at `commit-msg` and runs hygiene checks, shellcheck, hadolint and actionlint on `pre-commit`.

**Files:**

- Create: `.pre-commit-config.yaml`
- Create: `.gitignore`

**Key Decisions / Notes:**

- `default_install_hook_types: [pre-commit, commit-msg]` so a single `prek install` wires both stages.
- Hooks:
  - `compilerla/conventional-pre-commit` (commit-msg)
  - `pre-commit/pre-commit-hooks` (trailing-whitespace, end-of-file-fixer, check-yaml, check-json, check-merge-conflict)
  - `shellcheck-py`
  - `AleksaC/hadolint-py`
  - an actionlint variant that runs without Docker
  - All revs pinned to tags so Renovate can bump them (Task 4).
- `.gitignore`: `node_modules/`, `.codegraph/`. The PRD under `docs/prd/` stays tracked.
- Run prek via `uvx prek` locally (prek is not installed on this machine). The hook ids are `hadolint`, `shellcheck`, `actionlint`.
- Write temp files for the commit-msg check to `$TMPDIR` (session scratchpad), not `/tmp`.

**Definition of Done:**

- [ ] `uvx prek run --all-files` passes on the repo
- [ ] A commit-msg file containing `bad message` is rejected and one containing `feat: add toolbox` is accepted
- [ ] Verify: `uvx prek run --all-files && printf 'bad message\n' > /tmp/m1 && ! uvx prek run conventional-pre-commit --hook-stage commit-msg --commit-msg-filename /tmp/m1 && printf 'feat: add toolbox\n' > /tmp/m2 && uvx prek run conventional-pre-commit --hook-stage commit-msg --commit-msg-filename /tmp/m2`

### Task 2: Multi-stage hardened Dockerfile

**Objective:** Build the toolbox image from per-tool builder stages that fetch and checksum-verify pinned upstream binaries for `TARGETARCH`. The final Alpine stage contains only the runtime packages and those binaries, runs as non-root, and builds for both platforms.

**Files:**

- Create: `Dockerfile`
- Create: `.dockerignore`
- Create: `.hadolint.yaml`
- Create: `scripts/verify-checksum.sh`

**Key Decisions / Notes:**

- One named stage per downloaded tool so BuildKit fetches in parallel and caches per version. Each stage verifies the checksum (`sha256sum -c`) and fails the build on mismatch. Map `TARGETARCH` (amd64/arm64) to each project's asset naming (e.g. `x86_64`, `Linux_arm64`).
- Final stage:
  - `apk add --no-cache` the runtime packages
  - `COPY --from=<stage> --chmod=0755` each binary into `/usr/local/bin`
  - Remove setuid/setgid bits (`find / -xdev -perm /6000 -type f -exec chmod a-s {} +`)
  - `apk --purge del apk-tools` last, leaving the package database so scanners can still read it
  - `adduser -D -u 10001` and numeric `USER`
- Do not pin individual apk package versions, so `DL3018` is ignored in `.hadolint.yaml` with a comment pointing to Out of Scope. Disable no other rules.
- OCI labels: `org.opencontainers.image.source=https://github.com/mavogel/toolbox`, plus title, description and licenses.
- `.dockerignore` excludes everything except what the build needs (allowlist style: `*` then `!Dockerfile`).

**Definition of Done:**

- [ ] Image builds for both `linux/amd64` and `linux/arm64`
- [ ] `docker run --rm toolbox:dev id -u` prints `10001`
- [ ] A wrong checksum fails the build. Check this once by temporarily corrupting one expected hash locally, then revert.
- [ ] hadolint (via prek) passes on `Dockerfile`
- [ ] The built image stays under 750 MB (`docker image inspect --format '{{.Size}}'`; measured 617 MB arm64, 654 MB amd64), so size regressions are caught
- [ ] Verify: `docker buildx build --platform linux/arm64 --load -t toolbox:dev . && docker buildx build --platform linux/amd64 --load -t toolbox:dev-amd64 . && docker run --rm toolbox:dev id -u && test "$(docker image inspect toolbox:dev-amd64 --format '{{.Size}}')" -lt 786432000 && prek run hadolint --files Dockerfile`

### Task 3: Inventory-driven binary smoke test

**Objective:** Make the tool inventory the single source of truth for the smoke test. For every entry, the POSIX `sh` script asserts the binary is on `PATH`, is executable, and its version/help command exits 0. It also fails on any `/usr/local/bin` binary without an inventory entry, on running as root, and on any setuid/setgid file. The script is mounted read-only into the image and run as the image's default user, so it never ships in the image.

**Files:**

- Create: `tests/inventory.txt`
- Create: `tests/smoke.sh`

**Key Decisions / Notes:**

- `inventory.txt` format: one tool per line, `<binary> <check command…>`; `#` comments and blank lines ignored. Examples:
  - `kubectl kubectl version --client`
  - `helm helm version`
  - `ss ss -V`
  - `ip ip -V`
  - `traceroute traceroute --help 2>&1 | grep -qi usage`, because busybox applets exit non-zero on `--help`
- The script honours `INVENTORY=<path>` (default `/tests/inventory.txt`) so the negative test can feed a modified list.
- Output: one `PASS`/`FAIL <reason>` line per tool and a summary. Exit 1 if anything fails, after checking every tool rather than stopping at the first failure.
- Host invocation used by CI and the README: `docker run --rm -v "$PWD/tests:/tests:ro" <image> /tests/smoke.sh`.

**Definition of Done:**

- [ ] Smoke test passes on both arch images from Task 2, listing every inventory tool as PASS
- [ ] Adding a nonexistent tool line to a copy of the inventory makes the script exit 1 and name that tool
- [ ] Removing a `/usr/local/bin` tool's line from a copy of the inventory makes the script exit 1 with an "uninventoried binary" message
- [ ] Running the container as `--user 0` makes the script exit 1
- [ ] Verify: `docker run --rm -v "$PWD/tests:/tests:ro" toolbox:dev /tests/smoke.sh && docker run --rm -v "$PWD/tests:/tests:ro" toolbox:dev-amd64 /tests/smoke.sh`

### Task 4: Renovate configuration

**Objective:** Configure Renovate to update every Dockerfile tool `ARG`, the Alpine base digest, GitHub Actions (digest-pinned), pre-commit hook revs and npm devDependencies. Commit types are chosen so tool and base-image updates trigger a patch release and tooling updates do not.

**Files:**

- Create: `renovate.json`
- Modify: `.pre-commit-config.yaml`

**Key Decisions / Notes:**

- Extends:
  - `config:recommended`
  - `:semanticCommits`
  - `helpers:pinGitHubActionDigests`
  - `docker:pinDigests`
- Enable the `pre-commit` manager (it is opt-in).
- `customManagers` regex for `Dockerfile` matching `# renovate: datasource=(?<datasource>\S+) depName=(?<depName>\S+)( versioning=(?<versioning>\S+))?\nARG \S+_VERSION=(?<currentValue>\S+)`.
- `packageRules`:
  - Dockerfile custom-manager updates and Docker base-image updates → `semanticCommitType: fix`, scope `deps`, so they release
  - github-actions, pre-commit and npm → `chore`, scope `deps`
  - Group the Alpine digest across all stages into one PR.
- Add `renovatebot/pre-commit-hooks` `renovate-config-validator` to `.pre-commit-config.yaml`.

**Definition of Done:**

- [ ] The Renovate config validator passes
- [ ] The number of `# renovate:` annotations in `Dockerfile` equals the number of `ARG *_VERSION=` lines
- [ ] Verify: `npx --yes --package renovate@44.139.0 -- renovate-config-validator renovate.json && test "$(grep -c '^# renovate: datasource=github-releases' Dockerfile)" = "$(grep -c '^ARG .*_VERSION=' Dockerfile)"` (pinned because npx otherwise reuses a stale cached Renovate that rejects `managerFilePatterns`; the Alpine `ARG ALPINE_IMAGE` has its own annotation and regex)

### Task 5: semantic-release configuration

**Objective:** Add a lockfile-pinned semantic-release setup that releases from `main`. It analyses Conventional Commits, publishes a GitHub Release with generated notes, and exposes `version` and `published` to the workflow through `$GITHUB_OUTPUT`.

**Files:**

- Create: `package.json`
- Create: `package-lock.json`
- Create: `.releaserc.json`

**Key Decisions / Notes:**

- `package.json`: `"private": true`, devDependencies:
  - `semantic-release`
  - `@semantic-release/exec`
  - `conventional-changelog-conventionalcommits`
- No `@semantic-release/npm` and no `@semantic-release/git`. Nothing is committed back to protected `main`.
- `.releaserc.json`:
  - `branches: ["main"]`
  - `tagFormat: "v${version}"`
  - Plugins: commit-analyzer and release-notes-generator with preset `conventionalcommits`, `@semantic-release/github`, and `@semantic-release/exec`
  - The exec `successCmd` appends `version=${nextRelease.version}` and `published=true` to `$GITHUB_OUTPUT`.
- Pin the Node major in `package.json` `engines` and use the same major in the workflow.

**Definition of Done:**

- [ ] `npm ci` succeeds from the lockfile
- [ ] Every plugin named in `.releaserc.json` resolves
- [ ] Verify: `npm ci && node -e "const c=require('./.releaserc.json');for(const p of c.plugins){require.resolve(Array.isArray(p)?p[0]:p)}" && node -p "require('semantic-release/package.json').version"` (`semantic-release --version` prints "unknown")

### Task 6: Reusable CI workflow

**Objective:** Create `ci.yml`, triggered on `pull_request` and `workflow_call`. Its jobs are named exactly as the required checks: `lint` (prek on all files), `pr-title` (Conventional PR title, pull_request only), and a `build-test` matrix over both platforms. The matrix builds with buildx/QEMU, runs `tests/smoke.sh`, and on amd64 runs a Trivy scan.

**Files:**

- Create: `.github/workflows/ci.yml`
- Create: `.trivyignore`

**Key Decisions / Notes:**

- `build-test` matrix `platform: [linux/amd64, linux/arm64]` with job `name: build-test (${{ matrix.platform }})`. Steps:
  - `docker/setup-qemu-action`, `docker/setup-buildx-action`, then `docker/build-push-action` with `load: true`, `platforms: ${{ matrix.platform }}` and GHA cache scoped per platform, which `release.yml` reuses
  - Run the smoke test using the host invocation from Task 3
- Trivy: `aquasecurity/trivy-action` on the loaded image, `severity: CRITICAL`, `ignore-unfixed: true`, `exit-code: 1`.
- `pr-title`: `amannn/action-semantic-pull-request`. Squash merges make the PR title the commit message on `main`, so this is what semantic-release sees. When called from `release.yml` it is skipped via `if: github.event_name == 'pull_request'`.
- `lint`: install prek (`j178/prek-action` or `uvx prek`) and run `prek run --all-files`.
- Least privilege: top-level `permissions: contents: read`, plus `pull-requests: read` on `pr-title`. Actions pinned by tag; Renovate digest-pins them (Task 4).

**Definition of Done:**

- [ ] actionlint (via prek) passes on the workflow
- [ ] Job names match the Global Constraints check names exactly
- [ ] The `build-test` steps, run locally as the same docker commands, pass on both platforms. That is the Task 3 verify command.
- [ ] Verify: `uvx prek run --all-files && grep -E "name: (lint|pr-title|build-test \(\\$\{\{ matrix.platform \}\}\))" .github/workflows/ci.yml`

### Task 7: Release workflow

**Objective:** On push to `main`, `release.yml` runs `ci.yml` via `workflow_call`, then runs semantic-release. Only if a release was published does it build and push the multi-arch image with tags `X.Y.Z`/`X.Y`/`X`/`latest`, SBOM and max-mode provenance, sign it by digest with cosign keyless, and then force-move the git tag `vX` to the release tag.

**Files:**

- Create: `.github/workflows/release.yml`

**Key Decisions / Notes:**

- Jobs: `test` (`uses: ./.github/workflows/ci.yml`) → `release` (`needs: test`; `actions/checkout` with `fetch-depth: 0`, `npm ci`, `npx semantic-release` with `GITHUB_TOKEN`; outputs `published` and `version` from the exec plugin) → `publish` (`needs: release`, `if: needs.release.outputs.published == 'true'`).
- `publish`:
  - `actions/checkout` with `fetch-depth: 0` first, so `vX.Y.Z` exists locally for the floating-tag step
  - `docker/metadata-action` with `type=semver,pattern={{version}},value=v${{version}}` plus `{{major}}.{{minor}}`, `{{major}}` and `type=raw,value=latest`
  - `docker/login-action` to `ghcr.io` with `GITHUB_TOKEN`
  - `build-push-action` with both platforms, `push: true`, `sbom: true`, `provenance: mode=max`
  - `sigstore/cosign-installer`, then `cosign sign --yes ghcr.io/mavogel/toolbox@<digest>`
  - Finally `git tag -f vX vX.Y.Z && git push -f origin refs/tags/vX`
- Permissions per job:
  - release: `contents: write`, `issues: write`, `pull-requests: write`
  - publish: `contents: write`, `packages: write`, `id-token: write`
- `concurrency: { group: release, cancel-in-progress: false }`.
- No commits are pushed to `main`; only tags and releases are created. That is compatible with the Task 11 ruleset, which covers branches only.

**Definition of Done:**

- [ ] actionlint passes
- [ ] `publish` is gated on `published == 'true'`; the cosign sign step references the build step's `digest` output; the floating-tag step runs after signing in the same job
- [ ] Verify: `uvx prek run --all-files`

### Task 8: Drop the protection script (user-agreed)

**Objective:** Remove `scripts/protect-main.sh`: the user authorized applying the `protect-main` ruleset directly with `gh api` after the first push, so the script is unnecessary. The ruleset itself is applied in Task 11.

**Files:**

- Delete: `scripts/protect-main.sh`

**Key Decisions / Notes:**

- Ruleset payload (applied in Task 11): `deletion`, `non_fast_forward`, `required_linear_history`; `pull_request` with `required_approving_review_count: 0` and `allowed_merge_methods: ["squash"]`; `required_status_checks` with `strict_required_status_checks_policy: true` and the four Global Constraints contexts; `enforcement: active`, `conditions.ref_name.include: ["~DEFAULT_BRANCH"]`, no bypass actors.

**Definition of Done:**

- [ ] `scripts/protect-main.sh` no longer exists and nothing in the repo references it
- [ ] Verify: `test ! -e scripts/protect-main.sh && ! grep -rn "protect-main.sh" . --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=docs`

### Task 9: README documentation

**Objective:** Replace the stub README with:

- usage: `kubectl run`, `kubectl debug`, elevated-capability examples, `imagePullSecrets` for the private package
- the tool inventory
- the tag policy, including floating majors and how to verify the cosign signature
- local build and smoke-test commands
- contribution rules: prek install, Conventional Commits, squash merge
- Renovate behaviour
- the protection rules on `main`, including the GitHub plan note for private repos

**Files:**

- Modify: `README.md`

**Key Decisions / Notes:**

- The tool table lists every `tests/inventory.txt` entry; check that the counts match.
- `Trivial:` docs-only; validated by prek hygiene hooks and the count check below.

**Definition of Done:**

- [ ] Every binary in `tests/inventory.txt` appears in the README tool table
- [ ] Verify: `for t in $(grep -v '^#' tests/inventory.txt | awk 'NF{print $1}'); do grep -q "\`$t\`" README.md || echo "missing $t"; done | (! grep .) && uvx prek run --all-files`

### Task 10: Push and install Renovate

**Objective:** Publish the repository state and enable the external integration the agent cannot perform without git-write authority and a browser session.

**Owner:** User

**User Action:** Commit everything with `feat: initial container debug toolbox` and push to `origin main`. Install the Renovate GitHub App for `mavogel/toolbox` (already done).

**Files:**

- Modify: `README.md`

**Key Decisions / Notes:**

- The push to `main` happens before protection exists, and its `feat:` commit triggers the first release, `v1.0.0`.
- `README.md` is listed only so the review scope covers the committed state; this task makes no edit to it.

**Definition of Done:**

- [ ] `origin/main` exists and the Renovate app is installed
- [ ] Verify: `git ls-remote origin main`

### Task 11: Verify remote setup and first release

**Objective:** After the push, apply the `protect-main` ruleset with `gh api` (payload in Task 8 notes). Then confirm through read-only GitHub queries that the ruleset is active and the first release run succeeded, pull the published image and run the smoke test against it.

**Files:**

- Test: `tests/smoke.sh`

**Key Decisions / Notes:**

- If the ruleset API reports that a plan upgrade is required, record it as a blocked item with the API message; it is not a code defect.

**Definition of Done:**

- [ ] The ruleset is applied with `gh api -X POST repos/mavogel/toolbox/rulesets`, and `gh api repos/mavogel/toolbox/rulesets` lists `protect-main` with `enforcement: active`
- [ ] The latest `release.yml` run concluded `success`; GitHub Release `v1.0.0` exists; git tag `v1` resolves to the same commit as `v1.0.0`
- [ ] `ghcr.io/mavogel/toolbox:1` pulls, `cosign verify` succeeds for the repo's workflow identity, and the smoke test passes against it
- [ ] The package is private, so authenticate first: `gh auth token | docker login ghcr.io -u mavogel --password-stdin` (token needs `read:packages`)
- [ ] Verify: `gh auth token | docker login ghcr.io -u mavogel --password-stdin && gh run list --workflow release.yml --limit 1 --json conclusion && gh release view v1.0.0 && git fetch --tags --force && test "$(git rev-list -n1 v1)" = "$(git rev-list -n1 v1.0.0)" && docker run --rm -v "$PWD/tests:/tests:ro" ghcr.io/mavogel/toolbox:1 /tests/smoke.sh`

## Deviations

- Task 2 (tactical): the 250 MB size ceiling added after spec-review was infeasible — the extended tool binaries alone are ~536 MB (trivy 152 MB, k9s 117 MB) → ceiling set to 750 MB from the measured 617 MB (arm64) / 654 MB (amd64).
- Task 2 (tactical): hadolint cannot parse a nested heredoc, so the checksum helper is a real file → `scripts/verify-checksum.sh` (added to Task 2 `Files:`; `.dockerignore` allows it).
- Task 6 (user-agreed): Trivy found a fixable CRITICAL, CVE-2025-68121 (Go stdlib crypto/tls), in upstream `dive`, `grpcurl` and `vegeta` (built with Go 1.22–1.25) → keep the CRITICAL `--ignore-unfixed` gate and accept only that CVE in `.trivyignore` (client-side debug CLIs, not servers), with justification and review date; any other fixable CRITICAL still fails CI. Upstream Go tools also carry fixable HIGHs, which are not gated.
- Task 7 (tactical): the reusable `ci.yml` declares `pull-requests: read` on `pr-title`, so `release.yml`'s `test` job must grant `pull-requests: read` (plus `contents: read`) or the called workflow fails permission validation.
- Task 8 (tactical): the ruleset's `pull_request` rule also sets `allowed_merge_methods: ["squash"]`, matching the squash-merge design (the PR title becomes the commit semantic-release reads) → no new files.
- Task 8 (user-agreed): drop `scripts/protect-main.sh`; the agent applies the `protect-main` ruleset directly with `gh api` after the user pushes `origin main` (same rules and required checks as the script's payload). Delete `scripts/protect-main.sh`, remove the "Protecting `main`" section's script reference from `README.md` (keep the rule list), and update Tasks 10 and 11 accordingly (Task 10 user action becomes push + install the Renovate app; protection is applied by the agent).
