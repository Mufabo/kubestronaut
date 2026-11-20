#!/usr/bin/env bash
# Remove everything the lab created, then set it up again.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${here}/teardown.sh"
exec bash "${here}/setup.sh"
