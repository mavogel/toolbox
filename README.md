# toolbox

A minimal, hardened debugging toolbox for container environments such as
Kubernetes. One Alpine-based, non-root image with the network, DNS, TLS and
cluster-inspection binaries that production images leave out.

`ghcr.io/mavogel/toolbox` — `linux/amd64` and `linux/arm64`.

## Usage

Start a throwaway pod with a shell:

```sh
kubectl run toolbox --rm -it --image=ghcr.io/mavogel/toolbox:1 -- sh
```

Attach to a running pod (shares its network namespace) or a node:

```sh
kubectl debug -it <pod> --image=ghcr.io/mavogel/toolbox:1 --target=<container>
kubectl debug node/<node> -it --image=ghcr.io/mavogel/toolbox:1
```

The image runs as UID `10001` and grants no capabilities. For raw captures
(`tcpdump`, `nmap` raw modes) opt in at run time, for example with
`kubectl debug --profile=netadmin`, or a pod `securityContext` that runs as root
with `NET_RAW` / `NET_ADMIN`.

The GHCR package is private while the repository is. Create a pull secret from a
token with `read:packages` and reference it:

```sh
kubectl create secret docker-registry ghcr \
  --docker-server=ghcr.io --docker-username=<user> --docker-password=<token>
kubectl run toolbox --rm -it --image=ghcr.io/mavogel/toolbox:1 \
  --overrides='{"spec":{"imagePullSecrets":[{"name":"ghcr"}]}}' -- sh
```

## Tools

| Tool | Purpose |
|------|---------|
| `kubectl`, `helm`, `k9s`, `stern` | Kubernetes client, packages, terminal UI, multi-pod log tailing |
| `crictl`, `etcdctl` | Container runtime and etcd inspection |
| `grpcurl` | gRPC client |
| `trivy`, `dive` | Vulnerability scanning, image layer inspection |
| `vegeta` | HTTP load testing |
| `curl`, `openssl` | HTTP and TLS debugging |
| `jq`, `yq` | JSON and YAML processing |
| `dig`, `nslookup`, `host` | DNS lookups |
| `nc`, `nmap`, `mtr`, `traceroute`, `iperf3` | Connectivity, port scanning, path and throughput testing |
| `tcpdump`, `ip`, `ss` | Packet capture, interfaces and routes, sockets |

`tests/inventory.txt` is the source of truth for this list.

## Tags

Each release publishes an immutable `X.Y.Z` tag and floating `X.Y`, `X` and
`latest` tags, plus a floating git tag `vX`. Pin `X.Y.Z` for reproducible
debugging, or follow `X` for the latest compatible release.

Images are signed with cosign (keyless). Verify one with:

```sh
cosign verify ghcr.io/mavogel/toolbox:1 \
  --certificate-identity-regexp '^https://github.com/mavogel/toolbox/\.github/workflows/release\.yml@refs/heads/main$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Build and test locally

```sh
docker build -t toolbox:dev .
docker run --rm -v "$PWD/tests:/tests:ro" toolbox:dev /tests/smoke.sh
```

The smoke test checks that every binary in `tests/inventory.txt` is on `PATH`,
is executable and runs its version or help command. It also fails on any
uninventoried binary in `/usr/local/bin`, on running as root, and on setuid or
setgid files. Add new tools to the Dockerfile and to `tests/inventory.txt`
together.

## Contributing

Install the hooks once (needs [prek](https://github.com/j178/prek) or
pre-commit):

```sh
prek install
```

Commits and PR titles must follow
[Conventional Commits](https://www.conventionalcommits.org/); the `commit-msg`
hook rejects anything else. PRs are squash-merged, so the PR title is the
commit that reaches `main`.

Releases run automatically on every push to `main` via semantic-release:
`feat` bumps the minor version, `fix` the patch, and a `!` or `BREAKING CHANGE`
the major. Other types (`chore`, `docs`, `ci`, ...) do not release. A release
creates the GitHub Release and publishes the image to GHCR.

The release job and PR checks run Trivy and fail on a fixable `CRITICAL`
finding. Accepted exceptions live in `.trivyignore` with a justification and a
review date.

## Dependency updates

[Renovate](https://docs.renovatebot.com/) keeps everything current: tool
versions pinned as `ARG <TOOL>_VERSION` in the `Dockerfile`, the Alpine base
digest, GitHub Actions, pre-commit hook revisions and npm dev dependencies.
Tool and base-image updates are `fix(deps)` commits, so they release a patch
version; tooling updates are `chore(deps)` and do not.

## Protecting `main`

`main` is protected by a repository ruleset named `protect-main`: changes need a
pull request (squash merge only) with the `lint`, `pr-title` and both
`build-test` checks passing on an up-to-date branch, history stays linear, and
force-push and deletion are blocked. Rulesets on private repositories need a
paid GitHub plan.
