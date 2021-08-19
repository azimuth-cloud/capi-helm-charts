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
ARG KUBECTL_VERSIONS="v1.22.0 v1.21.4 v1.20.10 v1.19.14 v1.18.20 v1.17.17"
RUN set -ex; \
    OS_ARCH="$(uname -m)"; \
    case "$OS_ARCH" in \
        x86_64) kubectl_arch=amd64 ;; \
        aarch64) kubectl_arch=arm64 ;; \
        *) false ;; \
    esac; \
    for kubectl_version in $KUBECTL_VERSIONS; do \
        kubectl_minor_version=${kubectl_version%.*}; \
        kubectl_latest_version=${kubectl_latest_version:-$kubectl_minor_version}; \
        kubectl_url=https://dl.k8s.io/release/$kubectl_version/bin/linux/$kubectl_arch/kubectl; \
        kubectl_exe=/usr/bin/kubectl-$kubectl_minor_version; \
        curl -fsSL $kubectl_url -o $kubectl_exe; \
        chmod +x $kubectl_exe; \
    done; \
    ln -s /usr/bin/kubectl-$kubectl_latest_version /usr/bin/kubectl-latest

# This script uses the latest version to discover the version of the Kubernetes
# cluster before picking the correct version to use
COPY ./kubectl-shim /usr/bin/kubectl

ARG HELM_VERSION=v3.6.3
RUN set -ex; \
    OS_ARCH="$(uname -m)"; \
    case "$OS_ARCH" in \
        x86_64) helm_arch=amd64 ;; \
        aarch64) helm_arch=arm64 ;; \
        *) false ;; \
    esac; \
    curl -fsSL https://get.helm.sh/helm-$HELM_VERSION-linux-$helm_arch.tar.gz | \
      tar -xz --strip-components 1 -C /usr/bin linux-$helm_arch/helm
