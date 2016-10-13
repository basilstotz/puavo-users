#!/bin/sh

set -x
set -eu

sudo apt-get update
sudo apt-get install wget software-properties-common

# Apply puavo-standalone Ansible rules
wget -qO - https://github.com/opinsys/puavo-standalone/raw/master/setup.sh | sudo sh


# Install build dependencies
sudo make install-build-dep

# Disable minitest expectations. Breaks build on CI for some reason.
# See: https://github.com/seattlerb/minitest/issues/521
export MT_NO_EXPECTATIONS=1

# Build debian package
make deb

sudo script/test-install.sh


# Force organisations refresh...
curl -d foo=bar http://localhost:9292/v3/refresh_organisations

# Execute rest tests first as they are more low level
cd rest
make test

cd ..
make test

mkdir -p $HOME/results
cp ../puavo-*_* $HOME/results
