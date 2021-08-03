ARG UBI8_VERSION
FROM registry.access.redhat.com/ubi8/ubi-minimal:${UBI8_VERSION}
LABEL maintainer="code@uweeisele.eu"

ENV LANG="C.UTF-8"

ARG ZULU_OPENJDK_RELEASE ZULU_OPENJDK_VERSION
ENV ZULU_OPENJDK="zulu${ZULU_OPENJDK_RELEASE}-jdk-headless-${ZULU_OPENJDK_VERSION}"
LABEL openjdk=${ZULU_OPENJDK}

ENV JAVA_HOME="/usr/lib/jvm/zulu${ZULU_OPENJDK_RELEASE}"

RUN rpm --import https://www.azul.com/files/0xB1998361219BD9C9.txt \
    && rpm --install https://cdn.azul.com/zulu/bin/zulu-repo-1.0.0-1.noarch.rpm \
    && microdnf -y install ${ZULU_OPENJDK} git openssl tar gzip hostname shadow-utils \
    && useradd --no-log-init --create-home --shell /bin/bash appuser \
    && microdnf remove shadow-utils \
    && microdnf clean all \
    && rm -rf /var/lib/rpm \
    && rm -rf /tmp/*

USER appuser
WORKDIR /home/appuser