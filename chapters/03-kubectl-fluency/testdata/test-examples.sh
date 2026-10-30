#!/usr/bin/env bash
# Runs every jq and yq example shown in the Chapter 03 text against the sample
# data in this directory and compares the result with the output printed in the
# chapter. Needs jq and mikefarah/yq v4 on PATH; no cluster.
#   chapters/03-kubectl-fluency/testdata/test-examples.sh
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here" || exit 2
for tool in jq yq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "error: $tool is not installed (see versions.env for the pinned version)" >&2; exit 2; }
done
if [[ "$(yq --version 2>&1)" != *mikefarah* ]]; then
  echo "error: this is not mikefarah/yq v4 (the Go yq). Found: $(yq --version 2>&1)" >&2
  exit 2
fi

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
failures=0
# example <description> <expected output> <command run with bash>
example() {
  local desc=$1 want=$2 cmd=$3 got
  got="$(cd "$here" && bash -c "$cmd" 2>&1)"
  if [[ "$got" == "$want" ]]; then printf 'ok    %s\n' "$desc"
  else printf 'FAIL  %s\n--- expected\n%s\n--- got\n%s\n' "$desc" "$want" "$got"; failures=$((failures + 1)); fi
}
nl=$'\n'; tab=$'\t'

example "jq: names of all Pods" "web-prod-1${nl}web-prod-2${nl}db-dev-1${nl}batch-1" \
  "jq -r '.items[].metadata.name' pods.json"
example "jq: name and image as tab-separated columns" "web-prod-1${tab}nginx:1.27${nl}web-prod-2${tab}nginx:1.26${nl}db-dev-1${tab}busybox:1.36${nl}batch-1${tab}busybox:1.36" \
  "jq -r '.items[] | [.metadata.name, .spec.containers[0].image] | @tsv' pods.json"
example "jq: select by label" "web-prod-1${nl}web-prod-2" \
  "jq -r '.items[] | select(.metadata.labels.env == \"prod\") | .metadata.name' pods.json"
example "jq: unique images" "busybox:1.36${nl}nginx:1.26${nl}nginx:1.27" \
  "jq -r '[.items[].spec.containers[].image] | unique | .[]' pods.json"
example "jq: Pods per phase" "Pending 1${nl}Running 3" \
  "jq -r '.items | group_by(.status.phase) | .[] | \"\\(.[0].status.phase) \\(length)\"' pods.json"
example "jq: Pods whose containers restarted (note the ? operator)" "web-prod-2" \
  "jq -r '.items[] | select(any(.status.containerStatuses[]?; .restartCount > 0)) | .metadata.name' pods.json"
example "jq: Pods that have no containerStatuses yet" "batch-1" \
  "jq -r '.items[] | select(.status.containerStatuses | not) | .metadata.name' pods.json"

example "yq: read one field" "web-prod-1" "yq '.metadata.name' pod.yaml"
example "yq: names from a list" "web-prod-1${nl}web-prod-2${nl}db-dev-1${nl}batch-1" "yq '.items[].metadata.name' pods.yaml"
example "yq: select by label" "web-prod-1${nl}web-prod-2" \
  "yq '.items[] | select(.metadata.labels.env == \"prod\") | .metadata.name' pods.yaml"
example "yq: read the image" "nginx:1.27" "yq '.spec.containers[0].image' pod.yaml"
cp pod.yaml "${work}/edit.yaml"
example "yq -i: change the image in place" "nginx:1.28" \
  "yq -i '.spec.containers[0].image = \"nginx:1.28\"' '${work}/edit.yaml' && yq '.spec.containers[0].image' '${work}/edit.yaml'"
example "yq -i: append an environment variable" "- name: APP_MODE${nl}  value: test" \
  "yq -i '.spec.containers[0].env += [{\"name\": \"APP_MODE\", \"value\": \"test\"}]' '${work}/edit.yaml' && yq '.spec.containers[0].env' '${work}/edit.yaml'"
example "yq: strip server-populated fields" "apiVersion: v1${nl}kind: Pod${nl}metadata:${nl}  labels:${nl}    env: prod${nl}    tier: web${nl}  name: web-prod-1${nl}  namespace: ch03-kubectl${nl}spec:${nl}  containers:${nl}    - image: nginx:1.27${nl}      name: app" \
  "yq 'del(.status) | del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp)' pod.yaml | head -12"
example "yq: convert JSON to YAML" "env: prod${nl}tier: web" "yq -p=json -o=yaml '.items[0].metadata.labels' pods.json"

echo
if ((failures == 0)); then echo "All jq/yq examples match the chapter."; else echo "${failures} example(s) do not match."; exit 1; fi
