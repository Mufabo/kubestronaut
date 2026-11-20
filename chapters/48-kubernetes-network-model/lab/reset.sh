#!/usr/bin/env bash
# Setup always starts from a brand-new cluster, so reset is setup.
exec bash "$(dirname "${BASH_SOURCE[0]}")/setup.sh"
