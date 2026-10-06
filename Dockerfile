# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
# Container debug toolbox. Each tool is fetched and checksum-verified in its own
# builder stage; only the verified binaries are copied into the final image.

# renovate: datasource=docker depName=alpine
ARG ALPINE_IMAGE=alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

# ---------------------------------------------------------------------------
# Shared download helper: verify <file> <sums-file> (scripts/verify-checksum.sh)
# checks a file against a "<hash>  <name>" list and fails if it is not listed.
# ---------------------------------------------------------------------------
FROM ${ALPINE_IMAGE} AS fetch
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
RUN apk add --no-cache ca-certificates curl tar
COPY --chmod=0755 scripts/verify-checksum.sh /usr/local/bin/verify
WORKDIR /dl

# ---------------------------------------------------------------------------
# Tool stages
# ---------------------------------------------------------------------------
FROM fetch AS kubectl
ARG TARGETARCH
# renovate: datasource=github-releases depName=kubernetes/kubernetes
ARG KUBECTL_VERSION=v1.37.1
RUN curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" \
 && echo "$(curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl.sha256")  kubectl" > sums \
 && verify kubectl sums

FROM fetch AS helm
ARG TARGETARCH
# renovate: datasource=github-releases depName=helm/helm
ARG HELM_VERSION=v4.3.0
RUN f="helm-${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" \
 && curl -fsSLO "https://get.helm.sh/${f}" \
 && curl -fsSL "https://get.helm.sh/${f}.sha256sum" -o sums \
 && verify "$f" sums \
 && tar -xzf "$f" --strip-components=1 "linux-${TARGETARCH}/helm"

FROM fetch AS k9s
ARG TARGETARCH
# renovate: datasource=github-releases depName=derailed/k9s
ARG K9S_VERSION=v0.51.0
RUN f="k9s_Linux_${TARGETARCH}.tar.gz" \
 && curl -fsSLO "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/${f}" \
 && curl -fsSL "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/checksums.sha256" -o sums \
 && verify "$f" sums \
 && tar -xzf "$f" k9s

FROM fetch AS stern
ARG TARGETARCH
# renovate: datasource=github-releases depName=stern/stern
ARG STERN_VERSION=v1.34.0
RUN f="stern_${STERN_VERSION#v}_linux_${TARGETARCH}.tar.gz" \
 && curl -fsSLO "https://github.com/stern/stern/releases/download/${STERN_VERSION}/${f}" \
 && curl -fsSL "https://github.com/stern/stern/releases/download/${STERN_VERSION}/checksums.txt" -o sums \
 && verify "$f" sums \
 && tar -xzf "$f" stern

FROM fetch AS crictl
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
ARG TARGETARCH
# renovate: datasource=github-releases depName=kubernetes-sigs/cri-tools
ARG CRICTL_VERSION=v1.37.0
RUN f="crictl-${CRICTL_VERSION}-linux-${TARGETARCH}.tar.gz" \
 && curl -fsSLO "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/${f}" \
 && echo "$(curl -fsSL "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/${f}.sha256" | awk '{print $1}')  ${f}" > sums \
 && verify "$f" sums \
 && tar -xzf "$f" crictl

FROM fetch AS etcdctl
ARG TARGETARCH
# renovate: datasource=github-releases depName=etcd-io/etcd
ARG ETCD_VERSION=v3.7.2
RUN f="etcd-${ETCD_VERSION}-linux-${TARGETARCH}.tar.gz" \
 && curl -fsSLO "https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/${f}" \
 && curl -fsSL "https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/SHA256SUMS" -o sums \
 && verify "$f" sums \
 && tar -xzf "$f" --strip-components=1 "etcd-${ETCD_VERSION}-linux-${TARGETARCH}/etcdctl"

FROM fetch AS grpcurl
ARG TARGETARCH
# renovate: datasource=github-releases depName=fullstorydev/grpcurl
ARG GRPCURL_VERSION=v1.9.4
RUN case "$TARGETARCH" in amd64) a=x86_64 ;; *) a="$TARGETARCH" ;; esac \
 && f="grpcurl_${GRPCURL_VERSION#v}_linux_${a}.tar.gz" \
 && curl -fsSLO "https://github.com/fullstorydev/grpcurl/releases/download/${GRPCURL_VERSION}/${f}" \
 && curl -fsSL "https://github.com/fullstorydev/grpcurl/releases/download/${GRPCURL_VERSION}/grpcurl_${GRPCURL_VERSION#v}_checksums.txt" -o sums \
 && verify "$f" sums \
 && tar -xzf "$f" grpcurl

FROM fetch AS yq
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
ARG TARGETARCH
# renovate: datasource=github-releases depName=mikefarah/yq
ARG YQ_VERSION=v4.54.1
# The yq checksums file lists many hash algorithms per line; SHA-256 is the 18th
# hash column (see checksums_hashes_order), i.e. awk field 19.
RUN f="yq_linux_${TARGETARCH}" \
 && curl -fsSLO "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${f}" \
 && curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/checksums" \
      | awk -v f="$f" '$1 == f { print $19 "  " $1 }' > sums \
 && verify "$f" sums \
 && mv "$f" yq

FROM fetch AS dive
ARG TARGETARCH
# renovate: datasource=github-releases depName=wagoodman/dive
ARG DIVE_VERSION=v0.13.1
RUN f="dive_${DIVE_VERSION#v}_linux_${TARGETARCH}.tar.gz" \
 && curl -fsSLO "https://github.com/wagoodman/dive/releases/download/${DIVE_VERSION}/${f}" \
 && curl -fsSL "https://github.com/wagoodman/dive/releases/download/${DIVE_VERSION}/dive_${DIVE_VERSION#v}_checksums.txt" -o sums \
 && verify "$f" sums \
 && tar -xzf "$f" dive

FROM fetch AS trivy
ARG TARGETARCH
# renovate: datasource=github-releases depName=aquasecurity/trivy
ARG TRIVY_VERSION=v0.75.0
RUN case "$TARGETARCH" in amd64) a=64bit ;; arm64) a=ARM64 ;; esac \
 && f="trivy_${TRIVY_VERSION#v}_Linux-${a}.tar.gz" \
 && curl -fsSLO "https://github.com/aquasecurity/trivy/releases/download/${TRIVY_VERSION}/${f}" \
 && curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/${TRIVY_VERSION}/trivy_${TRIVY_VERSION#v}_checksums.txt" -o sums \
 && verify "$f" sums \
 && tar -xzf "$f" trivy

FROM fetch AS vegeta
ARG TARGETARCH
# renovate: datasource=github-releases depName=tsenart/vegeta
ARG VEGETA_VERSION=v12.13.0
RUN f="vegeta_${VEGETA_VERSION#v}_linux_${TARGETARCH}.tar.gz" \
 && curl -fsSLO "https://github.com/tsenart/vegeta/releases/download/${VEGETA_VERSION}/${f}" \
 && curl -fsSL "https://github.com/tsenart/vegeta/releases/download/${VEGETA_VERSION}/vegeta_${VEGETA_VERSION#v}_checksums.txt" -o sums \
 && verify "$f" sums \
 && tar -xzf "$f" vegeta

# ---------------------------------------------------------------------------
# Final image
# ---------------------------------------------------------------------------
FROM ${ALPINE_IMAGE}

LABEL org.opencontainers.image.title="toolbox" \
      org.opencontainers.image.description="Minimal, hardened debugging toolbox for container environments such as Kubernetes" \
      org.opencontainers.image.source="https://github.com/mavogel/toolbox"

SHELL ["/bin/ash", "-eo", "pipefail", "-c"]

RUN apk add --no-cache \
      bind-tools \
      ca-certificates \
      curl \
      iperf3 \
      iproute2 \
      jq \
      mtr \
      netcat-openbsd \
      nmap \
      openssl \
      tcpdump

COPY --from=kubectl --chmod=0755 /dl/kubectl /usr/local/bin/kubectl
COPY --from=helm    --chmod=0755 /dl/helm    /usr/local/bin/helm
COPY --from=k9s     --chmod=0755 /dl/k9s     /usr/local/bin/k9s
COPY --from=stern   --chmod=0755 /dl/stern   /usr/local/bin/stern
COPY --from=crictl  --chmod=0755 /dl/crictl  /usr/local/bin/crictl
COPY --from=etcdctl --chmod=0755 /dl/etcdctl /usr/local/bin/etcdctl
COPY --from=grpcurl --chmod=0755 /dl/grpcurl /usr/local/bin/grpcurl
COPY --from=yq      --chmod=0755 /dl/yq      /usr/local/bin/yq
COPY --from=dive    --chmod=0755 /dl/dive    /usr/local/bin/dive
COPY --from=trivy   --chmod=0755 /dl/trivy   /usr/local/bin/trivy
COPY --from=vegeta  --chmod=0755 /dl/vegeta  /usr/local/bin/vegeta

# Harden: drop setuid/setgid bits and the package manager (the package database
# stays so image scanners can still read it), then add the unprivileged user.
RUN find / -xdev -type f -perm /6000 -exec chmod a-s {} + \
 && apk --no-cache --purge del apk-tools \
 && adduser -D -u 10001 -h /home/toolbox toolbox

ENV HOME=/home/toolbox
WORKDIR /home/toolbox
USER 10001:10001
CMD ["/bin/sh"]
