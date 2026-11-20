#!/usr/bin/env bash
# Setup always starts from a fresh netlab container, so reset is setup.
exec bash "$(dirname "${BASH_SOURCE[0]}")/setup.sh"
