#!/usr/bin/env bash
# Reset = tear down everything the part owns, then rebuild its starting state.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${here}/setup.sh"
