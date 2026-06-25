#!/usr/bin/env python3
"""Format the controls/ pages for readability + rebuild controls/README.md.

SOURCE OF TRUTH = the controls/[NN]-<slug>.md pages themselves. Their prose, the
"In plain terms" blockquote and the "What would trigger an alert" section are
authored by hand and are NEVER rewritten by this script.

This is an IDEMPOTENT FORMATTER. Re-running it only (re)applies presentation:
  1. turns every `[NN]` reference into a clickable link to its component page,
     rendered WITH the brackets intact -> `[[NN]](NN-slug.md)`. You can author
     refs as plain `[NN]` and this script wraps them; re-running never double-wraps.
  2. splits long, semicolon-packed Prevention/Detection/Alert bullets into
     scannable sub-bullets,
  3. escapes `<...>` placeholders in the Type line so they actually render
     (markdown-it otherwise eats `<acct>` as an unknown HTML tag),
  4. rebuilds the controls/README.md index (consolidated list + per-component
     table) with the same clickable links,
  5. links the [NN] refs in the homepage prose too (fenced Mermaid blocks and
     inline code spans are skipped, so diagrams stay literal).

It is safe to run any number of times and will not lose content.

(Historical note: an earlier version of this file regenerated each page from a
terse in-script table, which silently dropped the rich hand-authored sections.
That destructive behaviour has been removed.)
"""
import os
import re
import glob

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "controls"))
HOME_README = os.path.abspath(os.path.join(HERE, "..", "README.md"))

# A bare reference `[NN]` that is NOT already wrapped (`[[NN]]`) and is NOT the
# label of a markdown link (`[NN](...)`). Lets the wrap be idempotent.
REF_RE = re.compile(r"(?<!\[)\[(\d{2})\](?!\]|\()")

# Legacy: strip the old reference-definition block this script used to append.
OLD_REF_BLOCK = re.compile(
    r"\n*<!-- ref-links:.*?<!-- end ref-links -->\n*", re.S)

PAGE_GLOB = "[0-9][0-9]-*.md"

# Consolidated, deduplicated controls shown above the index table.
# (control text, space-joined "[NN]" refs) — refs are linkified on output.
CONSOLIDATED = [
    ("Identity & access", [
        ("Phishing-resistant MFA at the IdP (doc-only)", "[04]"),
        ("SSO-only via permission sets", "[03]"),
        ("Least-privilege roles", "[29] [31] [32]"),
        ("No human has direct S3 — read-only via the EC2 UI", "[28]"),
    ]),
    ("Org guardrails", [
        ("S3 guardrail SCP", "[07]"),
        ("Strict account allow-list SCP", "[41]"),
        ("Permissions boundary caps SuperAdmin — no KMS", "[42]"),
        ("Protect-detection SCP — deny tampering with the monitors", "[60]"),
        ("RCP — deny S3 outside the org", "[08]"),
        ("Block Public Access on every bucket", ""),
    ]),
    ("Network isolation", [
        ("Private VPC — no IGW/NAT", "[10]"),
        ("All AWS access via VPC endpoints", "[13] [14] [15]"),
        ("Security-group-as-source rules, no CIDR", "[16] [17] [18]"),
    ]),
    ("Data protection", [
        ("Per-patient SSE-KMS CMKs", "[22]"),
        ("Vaultless tokenization", "[25]"),
        ("De-identified copy", "[21]"),
        ("TLS-only everywhere", ""),
    ]),
    ("Bucket access control", [
        ("Bucket policy VPC-lock on `aws:sourceVpce`", "[20]"),
        ("Access-point delegation for the redactor", "[26] [27]"),
    ]),
    ("Detection", [
        ("CloudTrail — multi-region + data events", "[33]"),
        ("GuardDuty managed threat detection", "[37]"),
        ("9 CloudWatch alarms", "[35]"),
        ("Detection self-protection — tamper alarm + SCP", "[60]"),
    ]),
    ("Alert & response", [
        ("SNS security alerts", "[36]"),
        ("Role-credential exfil alerting (GuardDuty InstanceCredentialExfiltration)", "[37]"),
        ("Change / CreateUser alerter with exclusion list", "[40]"),
        ("Per-patient key disable lever", "[22]"),
    ]),
]


def slug_map():
    """{ '20': '20-s3-sensitive.md', ... } from the files actually present."""
    m = {}
    for p in sorted(glob.glob(os.path.join(OUT, PAGE_GLOB))):
        fn = os.path.basename(p)
        m[fn[:2]] = fn
    return m


def escape_angles(s):
    """Render literal <...> placeholders instead of letting markdown-it eat them."""
    return s.replace("<", "&lt;").replace(">", "&gt;")


def split_bullet(label, content):
    """Split a Prevention/Detection/Alert bullet into sub-bullets when it is a
    semicolon-separated clause list. Genuine prose paragraphs (few semicolons but
    long) are left as a single bullet."""
    semis = content.count("; ")
    do_split = semis >= 2 or (semis == 1 and len(content) < 180)
    if not do_split:
        return [f"- **{label}:** {content}"]
    parts = [p.strip() for p in content.split("; ") if p.strip()]
    return [f"- **{label}:**"] + [f"  - {p}" for p in parts]


def _linkify_line(ln, smap, self_id, prefix):
    """Wrap bare [NN] -> [[NN]](path) on one line, skipping inline `code` spans."""
    segs = re.split(r"(`[^`]*`)", ln)  # odd indexes are code spans

    def repl(m):
        cid = m.group(1)
        if cid == self_id or cid not in smap:
            return m.group(0)
        return f"[[{cid}]]({prefix}{smap[cid]})"

    for i, seg in enumerate(segs):
        if not seg.startswith("`"):
            segs[i] = REF_RE.sub(repl, seg)
    return "".join(segs)


def linkify(text, smap, self_id=None, prefix=""):
    """Make [NN] refs clickable across `text`, skipping fenced code blocks
    (e.g. Mermaid) entirely so diagram source is left literal."""
    out, in_fence = [], False
    for ln in text.split("\n"):
        s = ln.lstrip()
        if s.startswith("```") or s.startswith("~~~"):
            in_fence = not in_fence
            out.append(ln)
        elif in_fence:
            out.append(ln)
        else:
            out.append(_linkify_line(ln, smap, self_id, prefix))
    return "\n".join(out)


def process_page(path, smap):
    self_id = os.path.basename(path)[:2]
    with open(path, encoding="utf-8") as f:
        text = f.read()
    text = OLD_REF_BLOCK.sub("\n", text).rstrip("\n")  # clean legacy ref block

    out = []
    for ln in text.split("\n"):
        if ln.startswith("**Type:**") or ln.startswith("- **Type:**"):
            out.append(escape_angles(ln))
            continue
        m = re.match(r"^- \*\*(Prevention|Detection|Alert):\*\*\s+(\S.*)$", ln)
        if m:
            out.extend(split_bullet(m.group(1), m.group(2)))
            continue
        out.append(ln)
    body = linkify("\n".join(out), smap, self_id).rstrip("\n") + "\n"
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(body)


def read_meta(path):
    """(id, name, type) parsed from a component page."""
    cid = os.path.basename(path)[:2]
    name = typ = ""
    with open(path, encoding="utf-8") as f:
        for ln in f:
            m = re.match(r"^# \[(\d{2})\] (.+)$", ln)
            if m:
                name = m.group(2).strip()
            m = re.match(r"^(?:- )?\*\*Type:\*\*\s+(.+)$", ln)
            if m:
                typ = m.group(1).strip()
            if name and typ:
                break
    return cid, name, escape_angles(typ)


def build_index(smap):
    pages = sorted(glob.glob(os.path.join(OUT, PAGE_GLOB)))
    metas = [read_meta(p) for p in pages]

    idx = [
        "# Controls index", "",
        "Consolidated controls for the whole system, then one tiny page per",
        "component. Every `[NN]` tag is a clickable link to its component page",
        "below (and matches the homepage diagrams). See also",
        "[OutOfScopeNotes.md](OutOfScopeNotes.md).", "",
        "## Controls applied (system-wide)", "",
    ]
    for theme, controls in CONSOLIDATED:
        idx += [f"**{theme}**", ""]
        for txt, refs in controls:
            idx.append(f"- {txt} {refs}".rstrip())
        idx.append("")
    idx += ["## Per-component pages", "",
            "| ID | Resource | Type |",
            "|----|----------|------|"]
    for cid, name, typ in metas:
        idx.append(f"| [{cid}] | [{name}]({smap[cid]}) | {typ} |")
    idx += ["", "[< home](../README.md)", ""]

    # linkify the assembled index: [NN] id-column + consolidated refs become
    # links; the name-column [text](slug.md) links are left untouched.
    text = linkify("\n".join(idx), smap).rstrip("\n") + "\n"
    with open(os.path.join(OUT, "README.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def link_home_readme(smap):
    """Make the [NN] refs in the homepage prose clickable too."""
    if not os.path.exists(HOME_README):
        return
    with open(HOME_README, encoding="utf-8") as f:
        text = f.read()
    text = OLD_REF_BLOCK.sub("\n", text)
    text = linkify(text, smap, prefix="controls/").rstrip("\n") + "\n"
    with open(HOME_README, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def main():
    smap = slug_map()
    pages = sorted(glob.glob(os.path.join(OUT, PAGE_GLOB)))
    for p in pages:
        process_page(p, smap)
    build_index(smap)
    link_home_readme(smap)
    print(f"formatted {len(pages)} control pages + README.md + linked homepage refs")


if __name__ == "__main__":
    main()
