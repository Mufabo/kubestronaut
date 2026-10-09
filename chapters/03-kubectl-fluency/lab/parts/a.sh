# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2329  # variables come from the sourcing script; check functions are passed by name
# Part a: shared seeded Pods. Sourced by common.sh.
NS=ch03-kubectl
A1=/tmp/ch03-a1.txt   # Pods with env=prod and tier=web
A2=/tmp/ch03-a2.txt   # "name image" for every Pod
A3=/tmp/ch03-a3.txt   # Pods that are not env=prod
A5=/tmp/ch03-api.yaml # generated manifest for Pod api
A6=/tmp/ch03-a6.txt   # type of pod.spec.terminationGracePeriodSeconds
A7=/tmp/ch03-a7.txt   # optional: unique images, via jq or yq

# The seeded Pods. Checks look only at these, so the Pod you create yourself in
# task 5 never changes the expected answers, whatever order you work in.
SEED="web-prod-1 web-prod-2 web-dev-1 db-prod-1 db-dev-1 cache-dev-1 batch-1"
only_seed() { awk -v seed="$SEED" 'BEGIN{n=split(seed,a," "); for(i=1;i<=n;i++) s[a[i]]=1} ($1 in s)'; }

part_setup() {
  require_lab_cluster
  lab_teardown_ns "$NS"
  rm -f "$A1" "$A2" "$A3" "$A5" "$A6" "$A7"
  lab_create_ns "$NS"
  kubectl -n "$NS" apply -f "${MANIFESTS}/a-pods.yaml" >/dev/null
  info "Waiting for the seed Pods to start (image pulls may take a moment)"
  wait_running "$NS" web-prod-1 web-prod-2 web-dev-1 db-prod-1 db-dev-1 cache-dev-1 batch-1
  info "Part a ready. Namespace: ${NS} (use -n ${NS}, or run: make use-namespace CH=3)"
}

# rows: name|env|tier|reviewed for every SEEDED Pod, one per line
pod_rows() {
  local all
  all="$(kubectl -n "$NS" get pods -o jsonpath='{range .items[*]}{.metadata.name}|{.metadata.labels.env}|{.metadata.labels.tier}|{.metadata.annotations.reviewed}{"\n"}{end}')" || return 1
  awk -F'|' -v seed="$SEED" 'BEGIN{n=split(seed,a," "); for(i=1;i<=n;i++) s[a[i]]=1} ($1 in s)' <<<"$all"
}

part_verify() {
  require_lab_cluster
  local rows
  t1() {
    rows="$(pod_rows)" && [[ -f "$A1" ]] &&
    [[ "$(norm_list "$A1")" == "$(awk -F'|' '$2=="prod" && $3=="web"{print $1}' <<<"$rows" | sort -u)" ]] &&
    [[ -n "$(norm_list "$A1")" ]]
  }
  t2() {
    local expected
    local all
    all="$(kubectl -n "$NS" get pods -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}')" &&
    expected="$(only_seed <<<"$all" | sort -u)" &&
    [[ -n "$expected" && -f "$A2" ]] &&
    [[ "$(grep -v '^[[:space:]]*$' "$A2" | tr -s ' \t' ' ' | sed -e 's/^ //' -e 's/ $//' | only_seed | sort -u)" == "$expected" ]]
  }
  t3() {
    rows="$(pod_rows)" && [[ -f "$A3" ]] &&
    [[ "$(norm_list "$A3" | only_seed)" == "$(awk -F'|' '$2!="prod"{print $1}' <<<"$rows" | sort -u)" ]] &&
    [[ -n "$(norm_list "$A3" | only_seed)" ]]
  }
  t4() {
    rows="$(pod_rows)" &&
    awk -F'|' '$3=="db"{db++; if($4!="true") bad=1} $3!="db"{if($4!="") bad=1} END{exit !(db>0 && !bad)}' <<<"$rows"
  }
  t5() {
    local text
    [[ -f "$A5" ]] && text="$(<"$A5")" &&
    [[ "$text" == *"kind: Pod"* && "$text" == *"name: api"* && "$text" == *"nginx:1.27"* ]] &&
    one_container "$NS" api &&
    [[ "$(jpod "$NS" api '{.spec.containers[0].image}')" == "nginx:1.27" ]] &&
    [[ "$(jpod "$NS" api '{.metadata.labels.app}')" == "api" ]] &&
    [[ "$(jpod "$NS" api '{.status.phase}')" == "Running" ]]
  }
  t6() {
    [[ -f "$A6" ]] && [[ "$(tr -d '[:space:]<>' < "$A6" | tr '[:upper:]' '[:lower:]')" == "integer" ]]
  }
  t7() {
    local expected
    expected="$(kubectl -n "$NS" get pods -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}' | sort -u)" &&
    [[ -n "$expected" && -f "$A7" && "$(norm_list "$A7")" == "$expected" ]]
  }
  check 1 "Pods labelled env=prod and tier=web are listed in ${A1}" "label selectors: kubectl get pods -l key=value,key2=value2" t1
  check 2 "every Pod and its image (name image, one per line) is in ${A2}" "custom-columns or JSONPath; the image is spec.containers[0].image" t2
  check 3 "Pods that are NOT env=prod are listed in ${A3}" "'!=' and 'notin' selectors also match Pods that have no env label at all" t3
  check 4 "every tier=db Pod has annotation reviewed=true, and no other Pod does" "kubectl annotate accepts a selector, -l" t4
  check 5 "Pod api (nginx:1.27, label app=api) exists and its manifest is saved in ${A5}" "generate the YAML with --dry-run=client -o yaml, save it, then apply it" t5
  check 6 "the type of terminationGracePeriodSeconds is saved in ${A6}" "kubectl explain pod.spec.terminationGracePeriodSeconds" t6
  check_optional 7 "unique images in use, from jq or yq, are saved in ${A7}" "kubectl get pods -o json | jq ...   or   kubectl get pods -o yaml | yq ..." t7
}

part_solve() {
  require_lab_cluster
  local k="kubectl -n $NS" out
  $k get pods -l env=prod,tier=web -o name | sed 's#^pod/##' > "$A1"
  $k get pods -o custom-columns=NAME:.metadata.name,IMAGE:.spec.containers[0].image --no-headers | sort > "$A2"
  $k get pods -l 'env!=prod' -o name | sed 's#^pod/##' > "$A3"
  $k annotate pods -l tier=db reviewed=true
  $k run api --image=nginx:1.27 --labels=app=api --dry-run=client -o yaml > "$A5"
  $k apply -f "$A5" >/dev/null
  out="$(kubectl explain pod.spec.terminationGracePeriodSeconds)"
  sed -n 's/^FIELD:.*<\([A-Za-z]*\)>.*/\1/p' <<<"$out" > "$A6"
  $k get pods -o jsonpath='{range .items[*]}{.spec.containers[*].image}{"\n"}{end}' | sort -u > "$A7"
  wait_running "$NS" api
}

part_teardown() {
  require_lab_cluster
  lab_teardown_ns "$NS"
  rm -f "$A1" "$A2" "$A3" "$A5" "$A6" "$A7"
  lab_restore_kubectx "${STATE}/kubectx"
  info "Part a removed."
}
