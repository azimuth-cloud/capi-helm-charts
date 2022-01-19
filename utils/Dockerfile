FROM debian:bullseye-slim

ENV UTILS_UID 1001
ENV UTILS_GID 1001
ENV UTILS_USER utils
ENV UTILS_GROUP utils
RUN groupadd --gid $UTILS_GID $UTILS_GROUP && \
    useradd \
      --no-create-home \
      --no-user-group \
      --gid $UTILS_GID \
      --shell /sbin/nologin \
      --uid $UTILS_UID \
      $UTILS_USER

RUN apt-get update && \
    apt-get install -y curl jq tini && \
    rm -rf /var/lib/apt/lists/*

COPY --from=hairyhenderson/gomplate:v3.10.0 /gomplate /usr/bin/gomplate

ARG KUBECTL_VN_1_20=v1.20.14
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

ARG KUBECTL_VN_1_21=v1.21.8
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

ARG KUBECTL_VN_1_22=v1.22.5
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

ARG KUBECTL_VN_1_23=v1.23.1
RUN set -ex; \
    OS_ARCH="$(uname -m)"; \
    case "$OS_ARCH" in \
        x86_64) kubectl_arch=amd64 ;; \
        aarch64) kubectl_arch=arm64 ;; \
        *) false ;; \
    esac; \
    curl -fsSL https://dl.k8s.io/release/${KUBECTL_VN_1_23}/bin/linux/${kubectl_arch}/kubectl -o /usr/bin/kubectl-v1.23; \
    chmod +x /usr/bin/kubectl-v1.23; \
    /usr/bin/kubectl-v1.23 version --client

ENV HELM_CACHE_HOME /tmp/helm/cache
ENV HELM_CONFIG_HOME /tmp/helm/config
ENV HELM_DATA_HOME /tmp/helm/data
ARG HELM_VERSION=v3.7.2
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

ENV KUBECTL_VN_LATEST v1.23
COPY ./scripts/* /usr/bin/

USER $UTILS_UID
ENTRYPOINT ["tini", "-g", "--"]
CMD ["bash"]
