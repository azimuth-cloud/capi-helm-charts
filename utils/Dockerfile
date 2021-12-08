#####
## Build specification for a container image containing tools that are useful
## for deploying applications
##
## It is designed to be run as a job inside the target cluster
#####

FROM alpine

# Install some useful tools
RUN apk add --no-cache curl jq

ARG KUBECTL_VN_1_20=v1.20.13
RUN set -ex; \
    OS_ARCH="$(uname -m)"; \
    case "$OS_ARCH" in \
        x86_64) kubectl_arch=amd64 ;; \
        aarch64) kubectl_arch=arm64 ;; \
        *) false ;; \
    esac; \
    curl -fsSL https://dl.k8s.io/release/${KUBECTL_VN_1_20}/bin/linux/${kubectl_arch}/kubectl -o /usr/bin/kubectl-v1.20; \
    chmod +x /usr/bin/kubectl-v1.20; \
    /usr/bin/kubectl-v1.20 version --client

ARG KUBECTL_VN_1_21=v1.21.7
RUN set -ex; \
    OS_ARCH="$(uname -m)"; \
    case "$OS_ARCH" in \
        x86_64) kubectl_arch=amd64 ;; \
        aarch64) kubectl_arch=arm64 ;; \
        *) false ;; \
    esac; \
    curl -fsSL https://dl.k8s.io/release/${KUBECTL_VN_1_21}/bin/linux/${kubectl_arch}/kubectl -o /usr/bin/kubectl-v1.21; \
    chmod +x /usr/bin/kubectl-v1.21; \
    /usr/bin/kubectl-v1.21 version --client

ARG KUBECTL_VN_1_22=v1.22.4
RUN set -ex; \
    OS_ARCH="$(uname -m)"; \
    case "$OS_ARCH" in \
        x86_64) kubectl_arch=amd64 ;; \
        aarch64) kubectl_arch=arm64 ;; \
        *) false ;; \
    esac; \
    curl -fsSL https://dl.k8s.io/release/${KUBECTL_VN_1_22}/bin/linux/${kubectl_arch}/kubectl -o /usr/bin/kubectl-v1.22; \
    chmod +x /usr/bin/kubectl-v1.22; \
    /usr/bin/kubectl-v1.22 version --client

# Tell Helm to use /tmp for cache, config and data
ENV HELM_CACHE_HOME /tmp/helm/cache
ENV HELM_CONFIG_HOME /tmp/helm/config
ENV HELM_DATA_HOME /tmp/helm/data
ARG HELM_VERSION=v3.7.1
RUN set -ex; \
    OS_ARCH="$(uname -m)"; \
    case "$OS_ARCH" in \
        x86_64) helm_arch=amd64 ;; \
        aarch64) helm_arch=arm64 ;; \
        *) false ;; \
    esac; \
    curl -fsSL https://get.helm.sh/helm-${HELM_VERSION}-linux-${helm_arch}.tar.gz | \
      tar -xz --strip-components 1 -C /usr/bin linux-${helm_arch}/helm; \
    helm version

# Install kustomize separately to kubectl so that we can use a more up-to-date version,
# even with older kubectls
ARG KUSTOMIZE_VERSION=v4.4.1
RUN set -ex; \
    OS_ARCH="$(uname -m)"; \
    case "$OS_ARCH" in \
        x86_64) kustomize_arch=amd64 ;; \
        aarch64) kustomize_arch=arm64 ;; \
        *) false ;; \
    esac; \
    curl -fsSL https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${KUSTOMIZE_VERSION}/kustomize_${KUSTOMIZE_VERSION}_linux_${kustomize_arch}.tar.gz | \
      tar -xz -C /usr/bin; \
    chmod +x /usr/bin/kustomize; \
    kustomize version

# Install helper scripts
ENV KUBECTL_VN_LATEST v1.22
COPY kubectl-wrapper.sh /usr/bin/kubectl
