#!/usr/bin/env bash
# The setup builds a brand-new cluster, so a reset is just another setup.
exec bash "$(dirname "${BASH_SOURCE[0]}")/setup.sh"
