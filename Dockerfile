##################
## base stage
##################
FROM ubuntu:jammy AS BASE

ARG DNSCRYPT_PROXY_VER=2.1.4

USER root

# Preconfigure debconf for non-interactive installation - otherwise complains about terminal
# Avoid ERROR: invoke-rc.d: policy-rc.d denied execution of start.
ARG DEBIAN_FRONTEND=noninteractive
ARG DISPLAY localhost:0.0
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
RUN dpkg-divert --local --rename --add /sbin/initctl
RUN ln -sf /bin/true /sbin/initctl
RUN echo "#!/bin/sh\nexit 0" > /usr/sbin/policy-rc.d

# configure apt
RUN apt-get update -q
RUN apt-get install --no-install-recommends -y -q apt-utils 2>&1 \
	| grep -v "debconf: delaying package configuration"
RUN apt-get install --no-install-recommends -y -q ca-certificates

# install dnscrypt-proxy
# Ubuntu repositories tend to have an older version, so install from github
RUN mkdir -p /tmp/dnscrypt-proxy
ENV DNSCRYPT_ARCHIVE=dnscrypt-proxy-linux_x86_64-${DNSCRYPT_PROXY_VER}.tar.gz
ADD https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/${DNSCRYPT_PROXY_VER}/${DNSCRYPT_ARCHIVE} /tmp/dnscrypt-proxy/${DNSCRYPT_ARCHIVE}
RUN mkdir /etc/dnscrypt-proxy
RUN tar -xvf /tmp/dnscrypt-proxy/${DNSCRYPT_ARCHIVE} -C /tmp/dnscrypt-proxy
RUN mv /tmp/dnscrypt-proxy/linux-x86_64/* /etc/dnscrypt-proxy  # note folder name slightly differs from archive name
RUN ln -s /etc/dnscrypt-proxy/dnscrypt-proxy /usr/bin/dnscrypt-proxy
RUN rm -rf /tmp/*

# apt cleanup
RUN apt-get autoremove -y -q
RUN apt-get -y -q clean
RUN rm -rf /var/lib/apt/lists/*

####################
## application stage
####################
FROM scratch
COPY --from=BASE / /
LABEL maintainer="elgeeko1"
LABEL source="https://github.com/elgeeko1/dnscrypt-proxy-docker"

EXPOSE 5053/udp
EXPOSE 5053/tcp

USER root

# configure container user
# default to a random UID to prevent collisions with host filesystem (also more secure)
ARG CONTAINER_USER=dnscrypt
ENV CONTAINER_USER=${CONTAINER_USER}
ARG CONTAINER_USER_UID=2000
ENV CONTAINER_USER_UID=${CONTAINER_USER_UID}
RUN adduser --disabled-password --gecos "" --shell /bin/bash --uid ${CONTAINER_USER_UID} ${CONTAINER_USER}

# configure filesystem
RUN chown -R dnscrypt:dnscrypt /etc/dnscrypt-proxy \
  && mkdir -p /var/cache/dnscrypt-proxy \
  && chown -R dnscrypt:dnscrypt /var/cache/dnscrypt-proxy
# persistent cache
VOLUME ["/var/cache/dnscrypt-proxy"]

USER ${CONTAINER_USER}
WORKDIR /etc/dnscrypt-proxy

# default configuration (quad9)
COPY app/dnscrypt-proxy.toml /etc/dnscrypt-proxy/dnscrypt-proxy.toml

ENTRYPOINT dnscrypt-proxy

HEALTHCHECK --interval=1m --timeout=10s --start-period=10s \
   CMD dnscrypt-proxy -resolve example.com
