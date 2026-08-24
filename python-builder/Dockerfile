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

FROM ubuntu:${HOST_UBUNTU}

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    python3 \
    python3-pip \
    python2 \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ponytail: pip is only guaranteed on 24.04+ because python3-pip is a Recommends
# (not a dependency) of python3 on Ubuntu <=23.10, hence the explicit apt install.
# The EXTERNALLY-MANAGED marker (24.04, PEP 668) is dropped so plain `pip install`
# works in this container; upgrade path: pin base to 24.04 only and use
# --break-system-packages instead.
# Bootstrap scripts are downloaded to a file, NOT piped into the interpreter:
# `curl ... | python2.7` exits 0 even when curl fails (pipeline status comes
# from python2.7, which exits 0 on empty stdin) — that masked failure is why
# "No module named pip" surfaced one step later. The get-pip bootstrap of 3.12+
# still hard-fails on the PEP 668 marker, so we delete the marker first and
# pass --break-system-packages, which only exists in pip 23+ (installed by apt
# on 24.04; 22.04's pip is pre-668 and ignores the flag harmlessly).
RUN rm -f /usr/lib/python3.*/EXTERNALLY-MANAGED \
    && curl -fsSL https://bootstrap.pypa.io/pip/get-pip.py -o /tmp/get-pip3.py \
    && python3 /tmp/get-pip3.py --break-system-packages \
    && python3 -m pip install -q --break-system-packages "pip>=24.2" setuptools wheel \
    && python3 -c "import pip, setuptools, wheel; print('py3 ok:', pip.__version__)" \
    && rm -f /tmp/get-pip3.py

# ponytail: no python2-pip package exists in Ubuntu 22.04+ repos (main/universe),
# so get-pip.py for 2.7 is the only route — it installs pip 20.3.4 (last py2
# release), which must then fetch the last py2 setuptools (44.1.1) and wheel
# (0.37.1) from PyPI itself. Every step is exit-checked and the result is
# verified at the end, so a PyPI/SSL hiccup fails the build instead of
# silently shipping an image without pip.
RUN curl -fsSL https://bootstrap.pypa.io/pip/2.7/get-pip.py -o /tmp/get-pip27.py \
    && python2.7 /tmp/get-pip27.py \
    && python2.7 -m pip install -q "pip==20.3.4" "setuptools==44.1.1" "wheel==0.37.1" \
    && python2.7 -m pip --version \
    && python2.7 -c "import pip, setuptools, wheel; print('py27 ok:', pip.__version__, setuptools.__version__, wheel.__version__)" \
    && rm -rf /root/.cache/pip /tmp/get-pip27.py

COPY python-builder/entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

WORKDIR /wrk

ENTRYPOINT ["/opt/entrypoint.sh"]
CMD ["/bin/bash"]
