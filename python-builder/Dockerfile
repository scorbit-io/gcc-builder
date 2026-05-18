# syntax=docker/dockerfile:1
# ==========================================
# Python wheel builder image
#
# Python 3 + 2.7 with pip/setuptools/wheel for pure-Python packaging.
# Used by Scorbit SDK (make python / make python27), not for cross-compilation.
#
# Usage (local, single platform):
#   make python-builder
#
# After pushing per-arch tags from each host, merge on Hub:
#   make manifest-python
# ==========================================

ARG HOST_UBUNTU=24.04

FROM --platform=$TARGETPLATFORM ubuntu:${HOST_UBUNTU}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    python3 \
    python2 \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    \
    && curl https://bootstrap.pypa.io/pip/get-pip.py | python3 \
    && curl https://bootstrap.pypa.io/pip/2.7/get-pip.py | python2.7 \
    && rm -rf /root/.cache/pip

RUN python3 -m pip install -q "pip>=24.2" setuptools wheel \
    && python2.7 -m pip install -q pip setuptools wheel

COPY python-builder/entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

WORKDIR /wrk

ENTRYPOINT ["/opt/entrypoint.sh"]
CMD ["/bin/bash"]
