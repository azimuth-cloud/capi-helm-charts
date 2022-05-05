FROM debian:bullseye-slim

ENV UTILS_UID 1001
ENV UTILS_GID 1001
ENV UTILS_USER utils
ENV UTILS_GROUP utils
ENV UTILS_HOME /home/utils
RUN groupadd --gid $UTILS_GID $UTILS_GROUP && \
    useradd \
      --home-dir $UTILS_HOME \
      --create-home \
      --gid $UTILS_GID \
      --shell /sbin/nologin \
      --uid $UTILS_UID \
      $UTILS_USER

RUN apt-get update && \
    apt-get install -y curl git jq python3 python3-pip tini && \
    rm -rf /var/lib/apt/lists/* && \
    pip install --no-cache ruamel.yaml

COPY --from=hairyhenderson/gomplate:v3.10.0 /gomplate /usr/bin/gomplate

ARG YQ_VN=v4.25.1
RUN set -ex; \
    OS_ARCH="$(uname -m)"; \
    case "$OS_ARCH" in \
        x86_64) yq_arch=amd64 ;; \
        aarch64) yq_arch=arm64 ;; \
        *) false ;; \
    esac; \
    curl -fsSL https://github.com/mikefarah/yq/releases/download/${YQ_VN}/yq_linux_${yq_arch} -o /usr/bin/yq; \
    chmod +x /usr/bin/yq; \
    /usr/bin/yq --version

ARG KUBECTL_VN_1_20=v1.20.15
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

ARG KUBECTL_VN_1_21=v1.21.12
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

ARG KUBECTL_VN_1_22=v1.22.9
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

ARG KUBECTL_VN_1_23=v1.23.6
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

ARG KUBECTL_VN_1_24=v1.24.0
RUN set -ex; \
    OS_ARCH="$(uname -m)"; \
    case "$OS_ARCH" in \
        x86_64) kubectl_arch=amd64 ;; \
        aarch64) kubectl_arch=arm64 ;; \
        *) false ;; \
    esac; \
    curl -fsSL https://dl.k8s.io/release/${KUBECTL_VN_1_24}/bin/linux/${kubectl_arch}/kubectl -o /usr/bin/kubectl-v1.24; \
    chmod +x /usr/bin/kubectl-v1.24; \
    /usr/bin/kubectl-v1.24 version --client

ENV HELM_CACHE_HOME /tmp/helm/cache
ENV HELM_CONFIG_HOME /tmp/helm/config
ENV HELM_DATA_HOME /tmp/helm/data
ARG HELM_VERSION=v3.8.2
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

ARG KUSTOMIZE_VERSION=v4.5.4
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

ENV KUBECTL_VN_LATEST v1.24
COPY ./bin/* /usr/bin/

USER $UTILS_UID
WORKDIR $UTILS_HOME
ENTRYPOINT ["tini", "-g", "--"]
CMD ["bash"]
