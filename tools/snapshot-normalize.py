#!/usr/bin/env python3
"""Read a kubectl JSON list on stdin; print a normalized snapshot.

Keeps what a read-only command must never change (identity, spec, data, labels,
annotations, ownership) and drops volatile fields (status, resourceVersion,
managedFields, timestamps, CNI-written annotations) so an idle cluster produces
identical snapshots."""
import json
import sys

doc = json.load(sys.stdin)
items = doc.get("items", []) if isinstance(doc, dict) else []
out = {}
for it in items:
    md = it.get("metadata", {})
    kind, name = it.get("kind", "?"), md.get("name", "?")
    if kind == "ConfigMap" and name == "kube-root-ca.crt":
        continue  # injected into every namespace by the control plane
    # Annotations the CNI plugin writes when a Pod's sandbox is created (for
    # example cni.projectcalico.org/podIP) are volatile, like status: they appear
    # between two reads of an idle Pod, so they are not part of the snapshot.
    annotations = {k: v for k, v in (md.get("annotations") or {}).items()
                   if not k.startswith("cni.projectcalico.org/")}
    entry = {
        "uid": md.get("uid"),
        "generation": md.get("generation"),
        "labels": md.get("labels"),
        "annotations": annotations or None,
        "owners": [o.get("uid") for o in md.get("ownerReferences", [])],
    }
    for key in ("spec", "data", "binaryData", "type", "rules", "roleRef", "subjects"):
        if key in it:
            entry[key] = it[key]
    out[f"{kind}/{name}"] = entry
print(json.dumps(out, indent=1, sort_keys=True))
