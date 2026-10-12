#!/usr/bin/env bash
# Reset = tear down everything the lab owns, then rebuild the starting state.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${here}/setup.sh"
