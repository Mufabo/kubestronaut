#!/usr/bin/env python3
"""A small stateful fake of the kubectl commands the lab framework and the
Chapter 03 lab use.

Used only by tools/test-harness.sh to test the FRAMEWORK and the lab SCRIPTS
without a cluster. It models: kubeconfig contexts, namespaces, Pods, ConfigMaps,
Secrets, ServiceAccounts, Services, RoleBindings, ClusterRoles, label selectors,
a JSONPath subset, and `auth can-i` for the built-in `view` role. It says
nothing about how real kubectl behaves; that is what CI on a real kind cluster
is for. State lives in the JSON file named by $FAKE_KUBE_STATE."""
import base64
import json
import os
import re
import sys

import yaml

PATH = os.environ["FAKE_KUBE_STATE"]
st = json.load(open(PATH, encoding="utf-8"))
KINDS = ("pods", "configmaps", "secrets", "serviceaccounts", "services", "rolebindings")
ALIASES = {
    "pod": "pods", "po": "pods", "pods": "pods",
    "configmap": "configmaps", "cm": "configmaps", "configmaps": "configmaps",
    "secret": "secrets", "secrets": "secrets",
    "serviceaccount": "serviceaccounts", "sa": "serviceaccounts", "serviceaccounts": "serviceaccounts",
    "service": "services", "svc": "services", "services": "services",
    "rolebinding": "rolebindings", "rolebindings": "rolebindings",
    "namespace": "namespaces", "ns": "namespaces", "namespaces": "namespaces",
    "clusterrole": "clusterroles", "clusterroles": "clusterroles",
}
KIND_NAME = {"pods": "Pod", "configmaps": "ConfigMap", "secrets": "Secret", "serviceaccounts": "ServiceAccount",
             "services": "Service", "rolebindings": "RoleBinding"}


def save():
    json.dump(st, open(PATH, "w", encoding="utf-8"))


def die(msg, code=1):
    sys.stderr.write(msg + "\n")
    sys.exit(code)


def new_uid():
    st["n"] += 1
    return f"uid-{st['n']}"


# ---------------------------------------------------------------- state upgrade
for _ns in st["namespaces"].values():
    for _k in KINDS:
        _ns.setdefault(_k, {})
    for _name, _rec in list(_ns["configmaps"].items()):
        if "metadata" not in _rec:  # legacy shape written by older test code
            _ns["configmaps"][_name] = {"kind": "ConfigMap", "apiVersion": "v1",
                                        "metadata": {"name": _name, "uid": _rec.get("uid", new_uid())},
                                        "data": _rec.get("data", {})}
for _name, _c in st["contexts"].items():
    _c.setdefault("cluster", "kind-kbook")
    _c.setdefault("user", "kind-kbook")
    _c.setdefault("namespace", "")


# ---------------------------------------------------------------- JSONPath subset
def _steps(p):
    steps, i = [], 0
    while i < len(p):
        if p[i] == ".":
            i += 1
            j = i
            while j < len(p) and p[j] not in ".[":
                j += 1
            if j > i:
                steps.append(("key", p[i:j]))
            i = j
        elif p[i] == "[":
            depth, j = 0, i
            while j < len(p):
                depth += (p[j] == "[") - (p[j] == "]")
                if depth == 0:
                    break
                j += 1
            steps.append(("idx", p[i + 1:j]))
            i = j + 1
        else:
            i += 1
    return steps


def _walk(nodes, steps):
    for kind, arg in steps:
        out = []
        if kind == "key":
            out = [n[arg] for n in nodes if isinstance(n, dict) and arg in n]
        elif arg == "*":
            for n in nodes:
                out.extend(n if isinstance(n, list) else list(n.values()) if isinstance(n, dict) else [])
        elif arg.startswith("?("):
            m = re.fullmatch(r'\?\(@\.([^=!]+?)\s*==\s*"(.*)"\)', arg)
            if not m:
                die(f"fake kubectl: unsupported filter {arg}")
            path, want = m.group(1), m.group(2)
            for n in nodes:
                for item in (n if isinstance(n, list) else []):
                    got = _walk([item], _steps("." + path))
                    if got and fmt(got[0]) == want:
                        out.append(item)
        else:
            for n in nodes:
                if isinstance(n, list):
                    try:
                        out.append(n[int(arg)])
                    except (IndexError, ValueError):
                        pass
        nodes = out
    return nodes


def fmt(v):
    if v is None:
        return ""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (dict, list)):
        return json.dumps(v)
    return str(v)


def render(obj, tmpl):
    toks, i = [], 0
    while i < len(tmpl):
        if tmpl[i] == "{":
            j = tmpl.index("}", i)
            toks.append(("expr", tmpl[i + 1:j]))
            i = j + 1
        else:
            j = tmpl.find("{", i)
            j = len(tmpl) if j < 0 else j
            toks.append(("text", tmpl[i:j]))
            i = j

    def run(tokens, ctx):
        out, k = [], 0
        while k < len(tokens):
            t, c = tokens[k]
            if t == "text":
                out.append(c)
            elif c.startswith("range "):
                depth, m = 1, k + 1
                while m < len(tokens):
                    if tokens[m][0] == "expr":
                        if tokens[m][1].startswith("range "):
                            depth += 1
                        elif tokens[m][1] == "end":
                            depth -= 1
                            if depth == 0:
                                break
                    m += 1
                items = _walk([ctx], _steps(c[6:].strip()))
                if len(items) == 1 and isinstance(items[0], list):
                    items = items[0]
                for it in items:
                    out.append(run(tokens[k + 1:m], it))
                k = m
            elif c == "end":
                pass
            elif c.startswith('"'):
                out.append(bytes(c[1:-1], "utf-8").decode("unicode_escape"))
            else:
                out.append(" ".join(fmt(v) for v in _walk([ctx], _steps(c))))
            k += 1
        return "".join(out)

    return run(toks, obj)


# ---------------------------------------------------------------- label selectors
def _split_terms(sel):
    terms, depth, cur = [], 0, ""
    for ch in sel:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            terms.append(cur)
            cur = ""
        else:
            cur += ch
    return terms + [cur]


def matches(labels, sel):
    labels = labels or {}
    for t in (x.strip() for x in _split_terms(sel or "")):
        if not t:
            continue
        m = re.fullmatch(r"(\S+)\s+(in|notin)\s*\((.*)\)", t)
        if m:
            vals = [v.strip() for v in m.group(3).split(",")]
            inside = labels.get(m.group(1)) in vals
            if (m.group(2) == "in") != inside and not (m.group(2) == "notin" and m.group(1) not in labels):
                return False
        elif "!=" in t:
            k, v = t.split("!=", 1)
            if labels.get(k.strip()) == v.strip():
                return False
        elif "=" in t:
            k, v = t.replace("==", "=").split("=", 1)
            if labels.get(k.strip()) != v.strip():
                return False
        elif t.startswith("!"):
            if t[1:] in labels:
                return False
        elif t not in labels:
            return False
    return True


# ---------------------------------------------------------------- argument parsing
raw = sys.argv[1:]
if not raw:
    die("fake kubectl: no arguments")
trailing = []
if "--" in raw:
    k = raw.index("--")
    raw, trailing = raw[:k], raw[k + 1:]

# ---- kubectl config -----------------------------------------------------------
if raw[0] == "config":
    cmd, rest = raw[1], raw[2:]
    flags = {a.split("=", 1)[0]: a.split("=", 1)[1] for a in rest if a.startswith("--") and "=" in a}
    pos = [a for a in rest if not a.startswith("-")]
    ctxs = st["contexts"]
    if cmd == "current-context":
        if not st["current"]:
            die("error: current-context is not set")
        print(st["current"])
    elif cmd == "view":
        out = next((rest[i + 1] for i, a in enumerate(rest) if a in ("-o", "--output")), None)
        out = out or next((a.split("=", 1)[1] for a in rest if a.startswith(("-o=", "--output="))), "")
        if "--minify" in rest and "..namespace" in out:
            sys.stdout.write(ctxs[st["current"]].get("namespace", "") if st["current"] else "")
        elif out.startswith("jsonpath="):
            cfg = {"current-context": st["current"],
                   "contexts": [{"name": n, "context": {"cluster": c["cluster"], "user": c["user"], "namespace": c["namespace"]}}
                                for n, c in ctxs.items()]}
            sys.stdout.write(render(cfg, out.split("=", 1)[1]))
        else:
            die("fake kubectl: unsupported 'config view' form")
    elif cmd == "set-context":
        name = st["current"] if "--current" in rest else pos[0]
        c = ctxs.setdefault(name, {"namespace": "", "cluster": "", "user": ""})
        for key in ("cluster", "user", "namespace"):
            if "--" + key in flags:
                c[key] = flags["--" + key]
        save()
    elif cmd == "use-context":
        if pos[0] not in ctxs:
            die(f'error: no context exists with the name: "{pos[0]}"')
        st["current"] = pos[0]
        save()
    elif cmd == "get-contexts":
        for n in ctxs:
            print(n)
    elif cmd == "delete-context":
        if pos[0] not in ctxs:
            die(f"error: cannot delete context {pos[0]}, not in config")
        del ctxs[pos[0]]
        save()
    elif cmd == "unset":
        _, name, field = pos[0].split(".")
        ctxs[name][field] = ""
        save()
    else:
        die(f"fake kubectl: unsupported config command {cmd}")
    sys.exit(0)

# ---- everything else ----------------------------------------------------------
ns_flag = ctx_flag = out = selector = file_arg = None
flags, pos = {}, []
i = 0
while i < len(raw):
    a = raw[i]
    if a == "-n":
        ns_flag = raw[i + 1]; i += 2; continue
    if a == "--context":
        ctx_flag = raw[i + 1]; i += 2; continue
    if a.startswith("--context="):
        ctx_flag = a.split("=", 1)[1]
    elif a in ("-o", "--output"):
        out = raw[i + 1]; i += 2; continue
    elif a.startswith("-o="):
        out = a.split("=", 1)[1]
    elif a in ("-l", "--selector"):
        selector = raw[i + 1]; i += 2; continue
    elif a.startswith("--selector="):
        selector = a.split("=", 1)[1]
    elif a == "-f":
        file_arg = raw[i + 1]; i += 2; continue
    elif a.startswith("--"):
        k, _, v = a[2:].partition("=")
        flags.setdefault(k, []).append(v if "=" in a else True)
    elif a.startswith("-") and len(a) > 1:
        pass
    else:
        pos.append(a)
    i += 1

ctx_name = ctx_flag or st["current"]
if ctx_name not in st["contexts"]:
    die(f'error: context "{ctx_name}" does not exist')
ns = ns_flag or st["contexts"][ctx_name].get("namespace") or "default"
nss = st["namespaces"]
flag = lambda k, d=None: (flags.get(k) or [d])[-1]


def pod_phase(image, restart):
    if "doesnotexist" in image:
        return "Pending"
    return "Succeeded" if restart == "Never" else "Running"


def need_ns(n):
    if n not in nss:
        die(f'Error from server (NotFound): namespaces "{n}" not found')
    return nss[n]


def get_obj(kind, n, name):
    obj = need_ns(n)[kind].get(name)
    if obj is None:
        die(f'Error from server (NotFound): {kind} "{name}" not found')
    return obj


def make_pod(n, name, image, labels, env, restart, command, args, port, container=None, annotations=None):
    c = {"name": container or name, "image": image}
    if command:
        c["command"] = command
    if args:
        c["args"] = args
    if env:
        c["env"] = [{"name": k, "value": v} for k, v in env]
    if port:
        c["ports"] = [{"containerPort": int(port)}]
    md = {"name": name, "namespace": n, "uid": new_uid(), "labels": dict(labels)}
    if annotations:
        md["annotations"] = dict(annotations)
    return {"apiVersion": "v1", "kind": "Pod", "metadata": md,
            "spec": {"containers": [c], "restartPolicy": restart, "nodeName": "kbook-worker"},
            "status": {"phase": pod_phase(image, restart)}, "_logs": ""}


def public(obj):
    return {k: v for k, v in obj.items() if not k.startswith("_")}


def parse_kv(items):
    return [tuple(x.split("=", 1)) for x in (items or []) if isinstance(x, str)]


def show(obj_or_list, is_list):
    if out is None or out == "name":
        if is_list:
            for o in obj_or_list["items"]:
                print(f"{KIND_NAME.get(o.get('_plural',''), o['kind']).lower()}/{o['metadata']['name']}" if out == "name" else o["metadata"]["name"])
        else:
            o = obj_or_list
            print(f"{o['kind'].lower()}/{o['metadata']['name']}" if out == "name" else o["metadata"]["name"])
    elif out.startswith("jsonpath="):
        sys.stdout.write(render(obj_or_list, out.split("=", 1)[1]))
    elif out == "json":
        print(json.dumps(obj_or_list))
    elif out == "yaml":
        print(yaml.safe_dump(obj_or_list, sort_keys=False), end="")
    elif out.startswith("custom-columns="):
        cols = [c.split(":", 1) for c in out.split("=", 1)[1].split(",")]
        rows = obj_or_list["items"] if is_list else [obj_or_list]
        if not flag("no-headers"):
            print("   ".join(h for h, _ in cols))
        for r in rows:
            print("   ".join(render(r, "{" + p + "}") for _, p in cols))
    else:
        die(f"fake kubectl: unsupported output {out}")


verb = pos[0] if pos else ""
if verb == "cluster-info":
    sys.exit(0)

# kind arguments may be `pod NAME` or `pod/NAME`
kind_arg, name = (pos[1] if len(pos) > 1 else ""), (pos[2] if len(pos) > 2 else "")
if "/" in kind_arg:
    kind_arg, name = kind_arg.split("/", 1)
kind = ALIASES.get(kind_arg.split(",")[0], kind_arg)

# ---------------------------------------------------------------- namespaces & cluster roles
if verb == "create" and kind == "namespaces":
    n = pos[2]
    if n in nss:
        die(f'Error from server (AlreadyExists): namespaces "{n}" already exists')
    nss[n] = {"uid": new_uid(), **{k: {} for k in KINDS}}
    save()
elif verb == "delete" and kind == "namespaces":
    n = pos[2]
    if n in nss:
        del nss[n]
        save()
    elif not flag("ignore-not-found"):
        die(f'Error from server (NotFound): namespaces "{n}" not found')
elif verb == "get" and kind == "namespaces":
    if name not in nss:
        die(f'Error from server (NotFound): namespaces "{name}" not found')
    sys.stdout.write(render({"metadata": {"uid": nss[name]["uid"], "name": name}}, out.split("=", 1)[1]))
elif verb == "create" and kind == "clusterroles":
    st["clusterroles"][name] = {"uid": new_uid()}
    save()
elif verb == "delete" and kind == "clusterroles":
    if name in st["clusterroles"]:
        del st["clusterroles"][name]
        save()
    elif not flag("ignore-not-found"):
        die(f'Error from server (NotFound): clusterroles "{name}" not found')
elif verb == "get" and kind == "clusterroles":
    if name not in st["clusterroles"]:
        die(f'Error from server (NotFound): clusterroles "{name}" not found')
    sys.stdout.write(render({"metadata": {"uid": st["clusterroles"][name]["uid"]}}, out.split("=", 1)[1]))

# ---------------------------------------------------------------- apply
elif verb == "apply":
    text = sys.stdin.read() if file_arg == "-" else open(file_arg, encoding="utf-8").read()
    for doc in yaml.safe_load_all(text):
        if not doc:
            continue
        k = doc["kind"]
        n = (doc.get("metadata") or {}).get("namespace") or ns
        plural = {v: p for p, v in KIND_NAME.items()}.get(k)
        if plural is None:
            die(f"fake kubectl: apply does not support kind {k}")
        space = need_ns(n)
        nm = doc["metadata"]["name"]
        if k == "Pod":
            spec = doc.get("spec", {})
            cs = spec.get("containers", [])
            restart = spec.get("restartPolicy", "Always")
            pod = make_pod(n, nm, cs[0]["image"], doc["metadata"].get("labels") or {},
                           [(e["name"], e.get("value", "")) for e in cs[0].get("env", [])], restart,
                           cs[0].get("command"), cs[0].get("args"), None, container=cs[0].get("name"),
                           annotations=doc["metadata"].get("annotations"))
            pod["spec"]["containers"] = cs
            if nm in space["pods"]:
                old = space["pods"][nm]
                pod["metadata"]["uid"] = old["metadata"]["uid"]
            space["pods"][nm] = pod
        else:
            obj = {"kind": k, "apiVersion": doc.get("apiVersion", "v1"),
                   "metadata": {"name": nm, "namespace": n, "uid": new_uid()}, "data": doc.get("data", {})}
            space[plural][nm] = obj
    save()

# ---------------------------------------------------------------- run / expose / create
elif verb == "run":
    nm = pos[1]
    image = flag("image")
    restart = flag("restart", "Always")
    labels = dict(parse_kv((flag("labels", "") or "").split(","))) if flag("labels") else {}
    pod = make_pod(ns, nm, image, labels, parse_kv(flags.get("env")), restart,
                   trailing if flag("command") else None, None if flag("command") else (trailing or None), flag("port"))
    if trailing and trailing[0] == "echo":
        pod["_logs"] = " ".join(trailing[1:])
    if str(flag("dry-run", "")).startswith("client"):
        doc = public(pod)
        doc["metadata"] = {"name": nm, "labels": labels, "creationTimestamp": None} if labels else {"name": nm, "creationTimestamp": None}
        doc["status"] = {}
        doc["spec"]["containers"][0]["resources"] = {}
        doc["spec"].pop("nodeName", None)
        print(yaml.safe_dump(doc, sort_keys=False), end="")
    else:
        space = need_ns(ns)
        if nm in space["pods"]:
            die(f'Error from server (AlreadyExists): pods "{nm}" already exists')
        space["pods"][nm] = pod
        save()
        print(f"pod/{nm} created")
elif verb == "expose":
    pod = get_obj("pods", ns, name)
    svc_name = flag("name") or name
    port = int(flag("port"))
    need_ns(ns)["services"][svc_name] = {
        "kind": "Service", "apiVersion": "v1", "metadata": {"name": svc_name, "namespace": ns, "uid": new_uid()},
        "spec": {"selector": dict(pod["metadata"].get("labels", {})),
                 "ports": [{"port": port, "targetPort": int(flag("target-port", port)), "protocol": "TCP"}]}}
    save()
elif verb == "create" and kind in ("configmaps", "secrets", "serviceaccounts", "rolebindings"):
    sub = pos[2] if kind == "secrets" else None  # `create secret generic NAME`
    nm = pos[3] if kind == "secrets" else name
    space = need_ns(ns)
    if nm in space[kind]:
        die(f'Error from server (AlreadyExists): {kind} "{nm}" already exists')
    lits = dict(parse_kv(flags.get("from-literal")))
    obj = {"kind": KIND_NAME[kind], "apiVersion": "v1", "metadata": {"name": nm, "namespace": ns, "uid": new_uid()}}
    if kind == "configmaps":
        obj["data"] = lits
    elif kind == "secrets":
        obj["type"] = "Opaque"
        obj["data"] = {k: base64.b64encode(v.encode()).decode() for k, v in lits.items()}
    elif kind == "rolebindings":
        obj["roleRef"] = {"kind": "ClusterRole", "name": flag("clusterrole")}
        obj["subjects"] = [{"kind": "ServiceAccount", "name": s.split(":")[1], "namespace": s.split(":")[0]}
                           for s in flags.get("serviceaccount", [])]
    space[kind][nm] = obj
    save()

# ---------------------------------------------------------------- change things
elif verb in ("label", "annotate"):
    field = "labels" if verb == "label" else "annotations"
    rest_args = pos[2:]
    assigns = parse_kv([x for x in rest_args if "=" in x])
    names = [x for x in rest_args if "=" not in x]
    if "/" in pos[1]:
        names = [pos[1].split("/", 1)[1]]
    space = need_ns(ns)
    if selector is not None or not names:
        targets = [p for p in space["pods"].values() if matches(p["metadata"].get("labels"), selector)]
    else:
        targets = [get_obj("pods", ns, names[0])]
    for p in targets:
        cur = p["metadata"].setdefault(field, {})
        for k, v in assigns:
            if k in cur and cur[k] != v and not flag("overwrite"):
                die(f"error: '{k}' already has a value ({cur[k]}), and --overwrite is false")
            cur[k] = v
    save()
elif verb == "set" and kind_arg == "image":
    target = pos[2].split("/", 1)[1]
    pod = get_obj("pods", ns, target)
    for assign in pos[3:]:
        cname, img = assign.split("=", 1)
        for c in pod["spec"]["containers"]:
            if cname in ("*", c["name"]):
                c["image"] = img
                break
        else:
            die(f'error: unable to find container named "{cname}"')
    save()
elif verb == "delete" and kind == "pods":
    space = need_ns(ns)
    if name in space["pods"]:
        del space["pods"][name]
        save()
    elif not flag("ignore-not-found"):
        die(f'Error from server (NotFound): pods "{name}" not found')
elif verb == "delete" and kind == "configmaps":
    space = need_ns(ns) if ns in nss else None
    if space and name in space["configmaps"]:
        del space["configmaps"][name]
        save()
    elif not flag("ignore-not-found"):
        die(f'Error from server (NotFound): configmaps "{name}" not found')

# ---------------------------------------------------------------- read things
elif verb == "logs":
    sys.stdout.write(get_obj("pods", ns, pos[1])["_logs"] + ("\n" if get_obj("pods", ns, pos[1])["_logs"] else ""))
elif verb == "explain":
    field = pos[1].split(".")[-1]
    ftype = {"terminationGracePeriodSeconds": "integer", "restartPolicy": "string", "containers": "[]Container"}.get(field, "string")
    print(f"KIND:       Pod\nVERSION:    v1\n\nFIELD: {field} <{ftype}>\n\nDESCRIPTION:\n    (fake) documentation for {field}.")
elif verb == "auth" and kind_arg == "can-i":
    vb, res = pos[2], pos[3]
    who = (flag("as", "") or "")
    allowed = True
    if who.startswith("system:serviceaccount:"):
        _, _, sa_ns, sa = who.split(":")
        allowed = False
        if ns == sa_ns and res.split("/")[0] in ("pods", "services", "configmaps", "serviceaccounts", "deployments") and vb in ("get", "list", "watch"):
            for rb in nss.get(ns, {}).get("rolebindings", {}).values():
                if rb["roleRef"]["name"] == "view" and any(s["name"] == sa and s["namespace"] == sa_ns for s in rb["subjects"]):
                    allowed = True
    print("yes" if allowed else "no")
    sys.exit(0 if allowed else 1)
elif verb == "get" and "," in kind_arg:  # aggregate listing used by the snapshot helper
    items = []
    for plural in kind_arg.split(","):
        plural = ALIASES.get(plural.split(".")[0], plural)
        for o in nss.get(ns, {}).get(plural, {}).values():
            if matches(o["metadata"].get("labels"), selector):
                items.append(public(o))
    show({"apiVersion": "v1", "kind": "List", "items": items}, True)
elif verb == "get" and kind in KINDS:
    if name:
        if out is None:
            get_obj(kind, ns, name)
        show(public(get_obj(kind, ns, name)), False) if out is not None else print(name)
    else:
        space = nss.get(ns, {k: {} for k in KINDS})
        items = [public(o) | {"_plural": kind} for o in space[kind].values() if matches(o["metadata"].get("labels"), selector)]
        for it in items:
            it.pop("_plural", None)
        show({"apiVersion": "v1", "kind": "List", "items": items}, True)
else:
    die(f"fake kubectl: unsupported command: {' '.join(sys.argv[1:])}")
