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
    rm -rf /var/lib/apt/lists/*

ARG KUBECTL_VN_1_24=v1.24.11
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

ARG KUBECTL_VN_1_25=v1.25.7
RUN set -ex; \
    OS_ARCH="$(uname -m)"; \
    case "$OS_ARCH" in \
        x86_64) kubectl_arch=amd64 ;; \
        aarch64) kubectl_arch=arm64 ;; \
        *) false ;; \
    esac; \
    curl -fsSL https://dl.k8s.io/release/${KUBECTL_VN_1_25}/bin/linux/${kubectl_arch}/kubectl -o /usr/bin/kubectl-v1.25; \
    chmod +x /usr/bin/kubectl-v1.25; \
    /usr/bin/kubectl-v1.25 version --client

ARG KUBECTL_VN_1_26=v1.26.2
RUN set -ex; \
    OS_ARCH="$(uname -m)"; \
    case "$OS_ARCH" in \
        x86_64) kubectl_arch=amd64 ;; \
        aarch64) kubectl_arch=arm64 ;; \
        *) false ;; \
    esac; \
    curl -fsSL https://dl.k8s.io/release/${KUBECTL_VN_1_26}/bin/linux/${kubectl_arch}/kubectl -o /usr/bin/kubectl-v1.26; \
    chmod +x /usr/bin/kubectl-v1.26; \
    /usr/bin/kubectl-v1.26 version --client

ENV HELM_CACHE_HOME /tmp/helm/cache
ENV HELM_CONFIG_HOME /tmp/helm/config
ENV HELM_DATA_HOME /tmp/helm/data
ARG HELM_VERSION=v3.11.2
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

ENV KUBECTL_VN_LATEST v1.26
COPY ./bin/* /usr/bin/

USER $UTILS_UID
WORKDIR $UTILS_HOME
ENTRYPOINT ["tini", "-g", "--"]
CMD ["bash"]
