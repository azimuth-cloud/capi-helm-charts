#####
## Build specification for a container image containing tools that are useful
## for deploying applications
##
## It is designed to be run as a job inside the target cluster
#####

FROM alpine

# Install some useful tools
RUN apk add --no-cache curl jq

# Because of the version skew policy, which only guarantees compatibility with a skew
# of one minor version, we must install a bunch of kubectl versions
# Install older versions first as it makes it more likely the cache can be used
ARG KUBECTL_VN_1_17=v1.17.17
RUN set -ex; \
    OS_ARCH="$(uname -m)"; \
    case "$OS_ARCH" in \
        x86_64) kubectl_arch=amd64 ;; \
        aarch64) kubectl_arch=arm64 ;; \
        *) false ;; \
    esac; \
    curl -fsSL https://dl.k8s.io/release/${KUBECTL_VN_1_17}/bin/linux/${kubectl_arch}/kubectl -o /usr/bin/kubectl-v1.17; \
    chmod +x /usr/bin/kubectl-v1.17; \
    /usr/bin/kubectl-v1.17 version --client

ARG KUBECTL_VN_1_18=v1.18.20
RUN set -ex; \
    OS_ARCH="$(uname -m)"; \
    case "$OS_ARCH" in \
        x86_64) kubectl_arch=amd64 ;; \
        aarch64) kubectl_arch=arm64 ;; \
        *) false ;; \
    esac; \
    curl -fsSL https://dl.k8s.io/release/${KUBECTL_VN_1_18}/bin/linux/${kubectl_arch}/kubectl -o /usr/bin/kubectl-v1.18; \
    chmod +x /usr/bin/kubectl-v1.18; \
    /usr/bin/kubectl-v1.18 version --client

ARG KUBECTL_VN_1_19=v1.19.14
RUN set -ex; \
    OS_ARCH="$(uname -m)"; \
    case "$OS_ARCH" in \
        x86_64) kubectl_arch=amd64 ;; \
        aarch64) kubectl_arch=arm64 ;; \
        *) false ;; \
    esac; \
    curl -fsSL https://dl.k8s.io/release/${KUBECTL_VN_1_19}/bin/linux/${kubectl_arch}/kubectl -o /usr/bin/kubectl-v1.19; \
    chmod +x /usr/bin/kubectl-v1.19; \
    /usr/bin/kubectl-v1.19 version --client

ARG KUBECTL_VN_1_20=v1.20.10
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

ARG KUBECTL_VN_1_21=v1.21.4
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

ARG KUBECTL_VN_1_22=v1.22.0
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
ARG HELM_VERSION=v3.6.3
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

ARG CLUSTERCTL_VERSION=v0.4.2
RUN set -ex; \
    OS_ARCH="$(uname -m)"; \
    case "$OS_ARCH" in \
        x86_64) clusterctl_arch=amd64 ;; \
        aarch64) clusterctl_arch=arm64 ;; \
        *) false ;; \
    esac; \
    curl -fsSL https://github.com/kubernetes-sigs/cluster-api/releases/download/${CLUSTERCTL_VERSION}/clusterctl-linux-${clusterctl_arch} -o /usr/bin/clusterctl; \
    chmod +x /usr/bin/clusterctl; \
    clusterctl version

# Install kustomize separately to kubectl so that we can use a more up-to-date version,
# even with older kubectls
ARG KUSTOMIZE_VERSION=v4.3.0
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
COPY ./scripts/ /usr/bin/
