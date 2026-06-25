#!/usr/bin/env python3
"""
Vaultless tokenization for the Synthea ePHI dataset.

WHY VAULTLESS (see docs/encryption-and-tokenization.md):
  A classic token vault stores token<->value rows and becomes a high-value target,
  a scaling bottleneck, and a single point of failure. Here every token is derived
  *cryptographically* from the value + a key, so there is NO lookup table:
    - reversible: detokenize() recovers the original by decrypting with the epoch key
    - deterministic: same value+field -> same token (enables joins / equality) via AES-SIV
    - epoch-tagged: token = "tok:v{EPOCH}:..." so we can ROTATE FORWARD cleanly:
        * mint a new DEK, mark it current for NEW writes,
        * keep old-epoch DEKs ONLY to decrypt old tokens,
        * retire old epochs lazily as data ages out  -> no mass re-tokenization.

DEMO vs PROD:
  - DEMO: epoch DEKs are derived with HKDF from a fixed, NON-SECRET test master so the
    script is self-contained and runnable offline.
  - PROD: each epoch DEK comes from `kms:GenerateDataKey` (envelope-encrypted, the
    wrapped DEK stored beside the epoch id); plaintext DEK lives only in memory. The
    per-patient KMS CMK additionally encrypts the whole object at rest in S3 (R15).

Outputs two views of every patient (the two buckets / the redactor's two faces):
  data/patients-sensitive/<id>.json  -> full record, direct identifiers TOKENIZED  (VPC-only bucket)
  data/patients-deident/<id>.json    -> Safe-Harbor de-identified, NO identifiers   (org-wide bucket + Lambda output)
And an index data/patient-index.json that Terraform reads to make a per-patient CMK.
"""
from __future__ import annotations

import base64
import datetime as _dt
import glob
import hashlib
import hmac
import json
import os
import sys

from cryptography.hazmat.primitives.ciphers.aead import AESSIV
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
FHIR_DIR = os.path.join(REPO, "data", "synthea-raw", "fhir")
OUT_SENS = os.path.join(REPO, "data", "patients-sensitive")
OUT_DEID = os.path.join(REPO, "data", "patients-deident")
INDEX = os.path.join(REPO, "data", "patient-index.json")

# ---- Key management (DEMO; see docstring) -------------------------------------------
CURRENT_EPOCH = 1
_DEMO_MASTER = b"ITH-DEMO-MASTER-KEY-NOT-FOR-PRODUCTION-USE-ONLY"


def epoch_key(epoch: int) -> bytes:
    """64-byte AES-256-SIV key for an epoch (HKDF in demo; KMS GenerateDataKey in prod)."""
    return HKDF(
        algorithm=hashes.SHA256(), length=64, salt=None,
        info=f"ith-tokenization-epoch-{epoch}".encode(),
    ).derive(_DEMO_MASTER)


_SIV_CACHE: dict[int, AESSIV] = {}


def _siv(epoch: int) -> AESSIV:
    if epoch not in _SIV_CACHE:
        _SIV_CACHE[epoch] = AESSIV(epoch_key(epoch))
    return _SIV_CACHE[epoch]


def tokenize(field: str, value: str | None, epoch: int = CURRENT_EPOCH) -> str | None:
    """Deterministic, reversible, epoch-tagged token. `field` is AAD => domain separation."""
    if value is None or value == "":
        return value
    ct = _siv(epoch).encrypt(value.encode("utf-8"), [field.encode("utf-8")])
    body = base64.urlsafe_b64encode(ct).decode("ascii").rstrip("=")
    return f"tok:v{epoch}:{body}"


def detokenize(field: str, token: str) -> str:
    """Inverse of tokenize() — proves vaultless reversibility (no lookup table)."""
    assert token.startswith("tok:v"), f"not a token: {token!r}"
    _, ver, body = token.split(":", 2)
    epoch = int(ver[1:])
    pad = "=" * (-len(body) % 4)
    ct = base64.urlsafe_b64decode(body + pad)
    return _siv(epoch).decrypt(ct, [field.encode("utf-8")]).decode("utf-8")


def pseudo_id(patient_id: str) -> str:
    """Stable non-reversible pseudonym for the de-identified view (keyed HMAC)."""
    return "p_" + hmac.new(epoch_key(CURRENT_EPOCH)[:32], patient_id.encode(), hashlib.sha256).hexdigest()[:16]


# ---- FHIR extraction -----------------------------------------------------------------
def _first(lst):
    return lst[0] if lst else None


def age_band(birth_date: str | None) -> str:
    if not birth_date:
        return "unknown"
    try:
        y = int(birth_date[:4])
        age = _dt.date.today().year - y
    except Exception:
        return "unknown"
    if age >= 90:               # HIPAA Safe Harbor: aggregate ages > 89
        return "90+"
    lo = (age // 10) * 10
    return f"{lo}-{lo + 9}"


def extract(bundle: dict) -> dict:
    patient, conditions = None, []
    for e in bundle.get("entry", []):
        r = e.get("resource", {})
        t = r.get("resourceType")
        if t == "Patient" and patient is None:
            patient = r
        elif t == "Condition":
            txt = (r.get("code", {}) or {}).get("text")
            if txt:
                conditions.append(txt)
    if patient is None:
        raise ValueError("no Patient resource in bundle")

    name = _first(patient.get("name", [])) or {}
    given = " ".join(name.get("given", []) or [])
    family = name.get("family", "")
    addr = _first(patient.get("address", [])) or {}
    ids = {i.get("system", ""): i.get("value", "") for i in patient.get("identifier", [])}
    tele = {c.get("system", ""): c.get("value", "") for c in patient.get("telecom", [])}

    return {
        "patient_id": patient.get("id"),
        "given": given,
        "family": family,
        "gender": patient.get("gender"),
        "birth_date": patient.get("birthDate"),
        "ssn": ids.get("http://hl7.org/fhir/sid/us-ssn", ""),
        "mrn": ids.get("http://hospital.smarthealthit.org", ""),
        "phone": tele.get("phone", ""),
        "email": tele.get("email", ""),
        "addr_line": " ".join(addr.get("line", []) or []),
        "city": addr.get("city", ""),
        "state": addr.get("state", ""),
        "postal": addr.get("postalCode", ""),
        "conditions": sorted(set(conditions)),
    }


def build_views(p: dict) -> tuple[dict, dict]:
    """sensitive (identifiers tokenized) and de-identified (identifiers removed)."""
    sensitive = {
        "schema": "ith.patient.sensitive/v1",
        "patient_id": p["patient_id"],
        "token_epoch": CURRENT_EPOCH,
        # direct identifiers -> reversible tokens (vaultless)
        "name_given": tokenize("name_given", p["given"]),
        "name_family": tokenize("name_family", p["family"]),
        "ssn": tokenize("ssn", p["ssn"]),
        "mrn": tokenize("mrn", p["mrn"]),
        "phone": tokenize("phone", p["phone"]),
        "email": tokenize("email", p["email"]),
        "address_line": tokenize("address_line", p["addr_line"]),
        "postal_code": tokenize("postal_code", p["postal"]),
        "birth_date": tokenize("birth_date", p["birth_date"]),
        # quasi/clinical kept (still PHI in context -> sensitive bucket only)
        "gender": p["gender"],
        "city": p["city"],
        "state": p["state"],
        "conditions": p["conditions"],
    }
    deident = {  # HIPAA Safe-Harbor-style: no direct identifiers at all
        "schema": "ith.patient.deident/v1",
        "pseudo_id": pseudo_id(p["patient_id"]),
        "gender": p["gender"],
        "age_band": age_band(p["birth_date"]),
        "state": p["state"],
        "conditions": p["conditions"],
    }
    return sensitive, deident


def main() -> int:
    os.makedirs(OUT_SENS, exist_ok=True)
    os.makedirs(OUT_DEID, exist_ok=True)
    files = sorted(
        f for f in glob.glob(os.path.join(FHIR_DIR, "*.json"))
        if not os.path.basename(f).lower().startswith(("hospital", "practitioner"))
    )
    if not files:
        print(f"ERROR: no FHIR bundles in {FHIR_DIR}", file=sys.stderr)
        return 1

    index = []
    for f in files:
        with open(f, "r", encoding="utf-8") as fh:
            bundle = json.load(fh)
        p = extract(bundle)
        sensitive, deident = build_views(p)
        pid = p["patient_id"]
        # short, DNS/alias-safe key id for the per-patient KMS CMK
        short = hashlib.sha256(pid.encode()).hexdigest()[:12]
        with open(os.path.join(OUT_SENS, f"{pid}.json"), "w", encoding="utf-8") as fh:
            json.dump(sensitive, fh, indent=2)
        with open(os.path.join(OUT_DEID, f"{pid}.json"), "w", encoding="utf-8") as fh:
            json.dump(deident, fh, indent=2)
        index.append({"patient_id": pid, "key_id": short,
                      "sensitive_object": f"patients/{pid}.json",
                      "deident_object": f"patients/{pid}.json"})

    with open(INDEX, "w", encoding="utf-8") as fh:
        json.dump({"token_epoch": CURRENT_EPOCH, "patients": index}, fh, indent=2)

    # self-check: prove round-trip reversibility on the first record
    sample = json.load(open(os.path.join(OUT_SENS, index[0]["patient_id"] + ".json"), encoding="utf-8"))
    assert detokenize("ssn", sample["ssn"]) , "detokenize failed"
    print(f"OK: {len(index)} patients -> sensitive+deident; index at {INDEX}")
    print(f"    round-trip check: ssn token detokenizes to '{detokenize('ssn', sample['ssn'])}'")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
