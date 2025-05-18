# SPDX-FileCopyrightText: (c) 2023 Jeff C. Jensen.
# SPDX-License-Identifier: MIT

# syntax=docker/dockerfile:1

##################
## base stage
##################
ARG BASEIMAGE=ubuntu:noble-20250415.1
FROM ${BASEIMAGE} AS base

ARG TARGETARCH
ENV TARGETARCH=${TARGETARCH}
ARG DNSCRYPT_PROXY_VER=2.1.8
ARG DNSCRYPT_PROXY_PACKAGE=https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/${DNSCRYPT_PROXY_VER}

USER root

# Preconfigure debconf for non-interactive installation - otherwise complains about terminal
# Avoid ERROR: invoke-rc.d: policy-rc.d denied execution of start, since systemd services aren't installed
ARG DEBIAN_FRONTEND=noninteractive
RUN printf '#!/bin/sh\nexit 0\n' > /usr/sbin/policy-rc.d
RUN chmod +x /usr/sbin/policy-rc.d

# configure apt
RUN apt-get update -qq
RUN apt-get install --no-install-recommends -y -q apt-utils 2>&1 \
	| grep -v "debconf: delaying package configuration"
RUN apt-get install --no-install-recommends -y -q ca-certificates

# install dnscrypt-proxy
RUN apt-get install --no-install-recommends -y -q wget
RUN mkdir -p dnscrypt-proxy
RUN mkdir /etc/dnscrypt-proxy
RUN RELEASE_FILENAME=${DNSCRYPT_PROXY_PACKAGE}/$( \
      case "${TARGETARCH}" in \
          amd64) echo "dnscrypt-proxy-linux_x86_64-${DNSCRYPT_PROXY_VER}.tar.gz" ;; \
          *)     echo "dnscrypt-proxy-linux_${TARGETARCH}-${DNSCRYPT_PROXY_VER}.tar.gz" ;; \
        esac \
      ) \
    && echo downloading ${RELEASE_FILENAME} \
    && wget -qO dnscrypt-proxy-linux-${TARGETARCH}-${DNSCRYPT_PROXY_VER}.tar.gz ${RELEASE_FILENAME}
RUN tar -xzf dnscrypt-proxy-linux-${TARGETARCH}-${DNSCRYPT_PROXY_VER}.tar.gz -C ./dnscrypt-proxy
RUN ls -la ./dnscrypt-proxy
RUN ls -la ./dnscrypt-proxy/linux-*/**
RUN cp -r ./dnscrypt-proxy/linux-*/* /etc/dnscrypt-proxy/
RUN ls -la /etc/dnscrypt-proxy/
RUN ln -s /etc/dnscrypt-proxy/dnscrypt-proxy /usr/bin/dnscrypt-proxy

####################
## application stage
####################
FROM ${BASEIMAGE}
LABEL maintainer="elgeeko"
LABEL org.opencontainers.image.title="dnscrypt-proxy 2"
LABEL org.opencontainers.description="Docker distribution of dnscrypt-proxy 2"
LABEL org.opencontainers.image.authors="Jeff C. Jensen <11233838+elgeeko1@users.noreply.github.com>"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.version="1.0.0"
LABEL org.opencontainers.image.url="https://hub.docker.com/r/xronosinc/ansible"
LABEL org.opencontainers.image.source="https://github.com/elgeeko1/dnscrypt-proxy-docker"

EXPOSE 5053/udp
EXPOSE 5053/tcp

USER root

# dnscrypt-proxy required packages
RUN apt-get update -qq \
    && apt-get install --no-install-recommends -y -q ca-certificates \
    && apt-get clean -y -q \
    && rm -rf /var/lib/apt/lists/*

# configure container user
# default UID unlikely to collide with host filesystem (also more secure)
ARG CONTAINER_USER=dnscrypt
ARG CONTAINER_USER_UID=2000
ENV CONTAINER_USER=${CONTAINER_USER}
ENV CONTAINER_USER_UID=${CONTAINER_USER_UID}
RUN useradd --create-home \
            --uid ${CONTAINER_USER_UID} \
            --shell /bin/bash \
            ${CONTAINER_USER}

# copy dnscrypt-proxy from base image
COPY --from=base \
     --chown=${CONTAINER_USER}:${CONTAINER_USER} \
     /etc/dnscrypt-proxy/ \
     /etc/dnscrypt-proxy/
COPY --from=base \
     --chown=${CONTAINER_USER}:${CONTAINER_USER} \
     /usr/bin/dnscrypt-proxy \
     /usr/bin/dnscrypt-proxy
COPY LICENSE /LICENSE
# persistent cache
RUN mkdir -p /var/cache/dnscrypt-proxy
RUN chown ${CONTAINER_USER}:${CONTAINER_USER} /var/cache/dnscrypt-proxy
VOLUME ["/var/cache/dnscrypt-proxy"]

USER ${CONTAINER_USER}
WORKDIR /etc/dnscrypt-proxy

# default configuration (quad9)
COPY app/dnscrypt-proxy.toml /etc/dnscrypt-proxy/dnscrypt-proxy.toml
# copy license for this image
ENTRYPOINT ["/usr/bin/dnscrypt-proxy"]

HEALTHCHECK --interval=1m --timeout=10s --start-period=10s \
   CMD dnscrypt-proxy -resolve example.com
