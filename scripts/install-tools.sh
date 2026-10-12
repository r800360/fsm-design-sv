#!/bin/bash
# install-tools.sh - installs the exact toolchain behind every result in this repository: the Ubuntu 26.04 packages
# below, pinned to the versions the results were produced with. Used by the Dockerfile and by GitHub Actions.
# Run as root on Ubuntu 26.04 (the Docker image pinned in the Dockerfile).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  iverilog=12.0-3 \
  verilator=5.032-1 \
  yosys=0.52-2 yosys-abc=0.52-2 \
  z3=4.13.3-1build1 \
  make g++ python3 git ca-certificates
echo "== toolchain"
iverilog -V 2>&1 | sed -n 1p
verilator --version
yosys -V
z3 --version
python3 --version
