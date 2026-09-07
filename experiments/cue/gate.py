#!/usr/bin/env python3
"""Fidelity gate for the kustomize -> CUE migration.

For every bundle that declares a `source`, renders that kustomize overlay and
the CUE bundle, and fails if the two disagree. Tiers are discovered on disk and
bundles from each tier's own `gateMeta`, so porting a workload enrols it here
automatically.

Both sides are decrypted before comparison, the way kustomize-controller
decrypts a source before building it. That is what makes the check meaningful
after the migration re-encrypted every secret: identical plaintext yields
different ciphertext, so only the plaintext is worth comparing. Decrypted
material exists in this process and in one mode-0700 temporary tree that is
shredded on exit. Nothing decrypted is ever written into the repository.
"""

import atexit
import base64
import difflib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ALLOWLIST = HERE / "allowlist.txt"

# kustomize's generator suffix: ten characters of consonants and digits.
HASH_SUFFIX = re.compile(r"^(?P<base>.+)-[bcdfghjklmnpqrstvwxz2456789]{10}$")


def sh(cmd, cwd=None, stdin=None, check=True):
    proc = subprocess.run(cmd, cwd=cwd, input=stdin, capture_output=True, text=True)
    if proc.returncode != 0:
        if not check:
            return None
        sys.exit(f"command failed: {' '.join(cmd)}\n{proc.stderr}")
    return proc.stdout


ROOT = pathlib.Path(sh(["git", "-C", str(HERE), "rev-parse", "--show-toplevel"]).strip())


def load_docs(text):
    """YAML to documents through yq, so the gate needs no Python YAML library."""
    docs = json.loads(sh(["yq", "ea", "-o=json", "-I=0", "[.]"], stdin=text))
    return [d for d in docs if isinstance(d, dict) and d.get("kind")]


def ident(doc):
    return f"{doc['kind']}/{doc.get('metadata', {}).get('name', '<unnamed>')}"


def dump(doc):
    return json.dumps(doc, indent=2, sort_keys=True) + "\n"


def decrypt(text):
    """Plaintext for a SOPS document, or the text unchanged if it carries none."""
    out = sh(
        ["sops", "decrypt", "--input-type", "yaml", "--output-type", "yaml", "/dev/stdin"],
        stdin=text,
        check=False,
    )
    return text if out is None else out


def decrypted_tree():
    """A copy of the working tree with every SOPS file decrypted, which is the
    state kustomize-controller builds from. Mode 0700, shredded by the caller."""
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="gate-"))
    os.chmod(tmp, 0o700)
    atexit.register(shred, tmp)  # the copy itself can fail, and it holds plaintext
    work = tmp / "repo"
    # Only what a kustomize overlay can reach. .direnv and result are symlinks
    # into the read-only store and would be dereferenced into unwritable copies.
    for tree in ("apps", "infrastructure", "components"):
        shutil.copytree(ROOT / tree, work / tree, symlinks=True)
    for path in list(work.rglob("*.yaml")) + list(work.rglob("*.yml")):
        text = path.read_text()
        if "sops:" not in text:
            continue
        plain = decrypt(text)
        if plain != text:
            path.write_text(plain)
    return tmp, work


def shred(tmp):
    for path in tmp.rglob("*"):
        if path.is_file():
            try:
                path.write_bytes(b"\0" * path.stat().st_size)
            except OSError:
                pass
    shutil.rmtree(tmp, ignore_errors=True)


def as_data(doc):
    """Secret.stringData is write-only sugar Kubernetes merges into data, so the
    two spellings are the same Secret. Fold one into the other rather than
    exempting the difference, and collapse whitespace inside the base64: kustomize
    emits it as a wrapped block scalar, so its line breaks land in the value."""
    if doc.get("kind") != "Secret":
        return doc
    doc = dict(doc)
    data = {
        k: "".join(v.split()) if isinstance(v, str) else v
        for k, v in (doc.get("data") or {}).items()
    }
    for key, value in (doc.pop("stringData", None) or {}).items():
        data[key] = base64.b64encode(value.encode()).decode()
    if data:
        doc["data"] = data
    doc.pop("sops", None)
    return doc


def substitute(obj, mapping):
    if isinstance(obj, dict):
        return {k: substitute(v, mapping) for k, v in obj.items()}
    if isinstance(obj, list):
        return [substitute(v, mapping) for v in obj]
    if isinstance(obj, str):
        return mapping.get(obj, obj)
    return obj


def strip_generator_hashes(golden, rendered):
    """Drop kustomize's content hash, but only where CUE emits the bare name at
    the same kind, so a name that merely looks hashed is left alone."""
    bare = {ident(d) for d in rendered}
    mapping = {}
    for doc in golden:
        match = HASH_SUFFIX.match(doc.get("metadata", {}).get("name", ""))
        if match and f"{doc['kind']}/{match['base']}" in bare:
            mapping[doc["metadata"]["name"]] = match["base"]
    return substitute(golden, mapping), mapping


def backup_secret_problems(rendered):
    """Every volsync repository the CUE side declares has to name a Secret the
    bundle ships. This is the half of #VolsyncRestic's contract CUE cannot check:
    it holds the file path, never the ciphertext. The golden side is exempt —
    there the chart creates the Secret, so it is not a document to look at."""
    secrets = {d["metadata"]["name"] for d in rendered if d.get("kind") == "Secret"}
    problems = []
    for doc in rendered:
        if doc.get("kind") != "HelmRelease":
            continue
        raw = (doc.get("spec", {}).get("values") or {}).get("rawResources") or {}
        for key, res in sorted(raw.items()):
            if not isinstance(res, dict) or res.get("kind") != "ReplicationSource":
                continue
            repo = res.get("spec", {}).get("spec", {}).get("restic", {}).get("repository")
            if repo not in secrets:
                problems.append(f"{ident(doc)} rawResources.{key}: no Secret named {repo}")
    return problems


def load_allowlist():
    entries = {}
    for lineno, raw in enumerate(ALLOWLIST.read_text().splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split(None, 2)
        if len(parts) < 3:
            sys.exit(f"{ALLOWLIST}:{lineno}: expected '<bundle> <kind>/<name> <reason>'")
        entries[(parts[0], parts[1])] = parts[2]
    return entries


def tiers():
    """A tier is a directory holding a .cue file named after it."""
    for tree in ("apps", "infrastructure"):
        if not (HERE / tree).is_dir():
            continue
        for path in sorted((HERE / tree).iterdir()):
            if (path / f"{path.name}.cue").exists():
                yield f"./{tree}/{path.name}"


def check(name, bundle, pkg, work, allowed, used):
    print(f"==> {name}  ({bundle['source']})")
    golden = load_docs(sh(["kustomize", "build", str(work / bundle["source"])]))

    rendered = load_docs(
        sh(["cue", "export", "-e", f'tier.rendered["{name}"]', "--out", "text", pkg], cwd=HERE)
    )
    for rel in bundle["secretFiles"]:
        rendered += load_docs(decrypt((HERE / rel).read_text()))

    golden, mapping = strip_generator_hashes(golden, rendered)
    for full, base in sorted(mapping.items()):
        print(f"    normalized generator hash: {full} -> {base}")

    left = {ident(d): as_data(d) for d in golden}
    right = {ident(d): as_data(d) for d in rendered}

    problems = []
    for key in sorted(set(left) | set(right)):
        if key not in right:
            problems.append((key, "missing from CUE", None))
        elif key not in left:
            problems.append((key, "emitted by CUE only", None))
        elif left[key] != right[key]:
            diff = difflib.unified_diff(
                dump(left[key]).splitlines(True),
                dump(right[key]).splitlines(True),
                "kustomize",
                "cue",
            )
            problems.append((key, "differs", "".join(diff)))

    failures = 0
    for key, kind, detail in problems:
        if (name, key) in allowed:
            used.add((name, key))
            print(f"    allowed   {key}: {kind} — {allowed[(name, key)]}")
            continue
        failures += 1
        print(f"    FAIL      {key}: {kind}")
        for line in (detail or "").splitlines():
            print(f"      {line}")

    for problem in backup_secret_problems(rendered):
        failures += 1
        print(f"    FAIL      {problem}")

    if not problems:
        print(f"    {len(left)} resources, identical")
    return failures


def workload_count():
    trees = (
        ROOT / "apps" / "base",
        ROOT / "infrastructure" / "base",
        ROOT / "infrastructure" / "nyx" / "config",
    )
    return sum(1 for t in trees for p in t.iterdir() if (p / "kustomization.yaml").exists())


def main():
    allowed = load_allowlist()
    used = set()
    failures = 0
    ported = 0

    _, work = decrypted_tree()
    if True:
        for pkg in tiers():
            meta = json.loads(
                sh(["cue", "export", "-e", "tier.gateMeta", "--out", "json", pkg], cwd=HERE)
            )
            for name in sorted(meta):
                if not meta[name]["source"]:
                    print(f"==> {name}: not ported, skipped")
                    continue
                ported += 1
                failures += check(name, meta[name], pkg, work, allowed, used)

    for bundle, resource in sorted(set(allowed) - used):
        print(f"!!! stale allowlist entry: {bundle} {resource}")
        failures += 1

    print(f"\n{ported} of {workload_count()} workloads ported, {failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
