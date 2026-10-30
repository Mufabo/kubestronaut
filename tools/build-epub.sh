#!/usr/bin/env bash
# Build the book as an EPUB: the README as the introduction, Chapters 01 to 39 in
# order, then the mock exams' question pages as an appendix (their solutions stay
# out). Mermaid diagrams become images (tools/epub/filter.lua).
#   tools/build-epub.sh [output]      default: dist/kubestronaut-book.epub
# Needs pandoc (PANDOC_VERSION) and, for the diagrams, mermaid-cli: set MMDC, or
# have npx, which fetches MERMAID_CLI_VERSION.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${here}/.." && pwd)"
cd "$root"
set -a
# shellcheck source=/dev/null
source "${root}/versions.env"
set +a

out="${1:-dist/kubestronaut-book.epub}"
command -v pandoc >/dev/null 2>&1 || { echo "error: pandoc not found (pinned: ${PANDOC_VERSION})" >&2; exit 1; }
have="$(pandoc --version | head -1 | awk '{print $2}')"
[[ "$have" == "$PANDOC_VERSION" ]] || echo "warning: pandoc ${have}, but versions.env pins ${PANDOC_VERSION}" >&2
if [[ -z "${MMDC:-}" ]]; then
  if command -v mmdc >/dev/null 2>&1; then MMDC=mmdc
  else MMDC="npx -y @mermaid-js/mermaid-cli@${MERMAID_CLI_VERSION}"
  fi
fi
export MMDC

export MERMAID_OUT="${root}/build/mermaid"
rm -rf "${root}/build" && mkdir -p "$MERMAID_OUT" "$(dirname "$out")"

inputs=(README.md)
for f in chapters/[0-9][0-9]-*/[0-9][0-9]-*.md; do inputs+=("$f"); done
inputs+=(mock-exams/README.md)
for d in mock-exams/*/; do
  name="$(basename "$d")"
  [[ -f "${d}${name}.md" ]] && inputs+=("${d}${name}.md")
done

edition="$(date -u +%Y-%m-%d)"
commit="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "==> Building ${out} from ${#inputs[@]} files (edition ${edition}, ${commit})"
pandoc --from=gfm --to=epub3 \
  --metadata-file=book/metadata.yaml \
  --metadata=subtitle:"Edition ${edition} (${commit})" \
  --metadata=date:"${edition}" \
  --css=book/epub.css \
  --toc --toc-depth=2 --split-level=1 \
  --lua-filter=tools/epub/filter.lua \
  --resource-path=".:${MERMAID_OUT}" \
  --output="$out" \
  "${inputs[@]}"
echo "==> ${out} ($(du -h "$out" | cut -f1))"
