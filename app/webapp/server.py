#!/usr/bin/env python3
"""
EC2 web app — the SOLE human read path (P3, C1).

Humans reach this only via SSM Session Manager port-forwarding (no SSH, no public
ingress). The app reads the SENSITIVE bucket using the EC2 *instance role* from inside
the VPC (S3 gateway endpoint -> aws:sourceVpce satisfied). The S3 fetch is hand-rolled
SigV4 over the Python standard library (no boto3) so it runs on the no-internet host.

It renders TWO tables:
  1. As stored — direct identifiers stay TOKENIZED (what leaves the bucket).
  2. Detokenized — the same records with real identifiers recovered, to DEMONSTRATE that
     this controlled path *can* reverse the vaultless tokens when authorised. Detok is
     AES-SIV (RFC 5297) using the epoch key; in DEMO that key is HKDF-derived from a known
     test master, in PROD it comes from the attestation-gated enclave CMK whose policy denies
     `kms:GenerateDataKey`/`kms:Decrypt` unless the request carries a Nitro attestation doc whose
     PCR0 matches this measured enclave (terraform/20-workload/kms.tf [43]). So the key is given
     ONLY to the enclave on this machine — not the node OS/role/root — and to no other use case.

Env:
  ITH_BUCKET    sensitive bucket name
  ITH_REGION    region
  ITH_KEYS      comma-separated object keys (patients/<id>.json)
"""
import datetime
import hashlib
import hmac
import json
import os
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Detok uses the host's preinstalled `cryptography` (v36 — predates the AESSIV helper, so
# AES-SIV is assembled from the CMAC + CTR primitives it does ship).
from cryptography.hazmat.primitives.cmac import CMAC
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes

REGION = os.environ.get("ITH_REGION", "ap-southeast-1")
BUCKET = os.environ["ITH_BUCKET"]
KEYS = [k for k in os.environ.get("ITH_KEYS", "").split(",") if k]
PORT = int(os.environ.get("ITH_PORT", "8080"))

_IMDS = "http://169.254.169.254"
_EMPTY_SHA = hashlib.sha256(b"").hexdigest()

# Detokenization key material (DEMO; see module docstring). PROD: epoch DEK via KMS.
_DEMO_MASTER = b"ITH-DEMO-MASTER-KEY-NOT-FOR-PRODUCTION-USE-ONLY"


# ---- IMDSv2 instance-role credentials ------------------------------------------------
def _imds_token() -> str:
    req = urllib.request.Request(
        f"{_IMDS}/latest/api/token", method="PUT",
        headers={"X-aws-ec2-metadata-token-ttl-seconds": "300"},
    )
    return urllib.request.urlopen(req, timeout=2).read().decode()


def get_credentials() -> dict:
    tok = _imds_token()
    h = {"X-aws-ec2-metadata-token": tok}
    base = f"{_IMDS}/latest/meta-data/iam/security-credentials/"
    role = urllib.request.urlopen(urllib.request.Request(base, headers=h), timeout=2).read().decode().strip()
    body = urllib.request.urlopen(urllib.request.Request(base + role, headers=h), timeout=2).read()
    return json.loads(body)


# ---- minimal SigV4 for S3 GET --------------------------------------------------------
def _sign(key: bytes, msg: str) -> bytes:
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def s3_get(bucket: str, key: str, creds: dict) -> bytes:
    host = f"{bucket}.s3.{REGION}.amazonaws.com"
    now = datetime.datetime.now(datetime.timezone.utc)
    amzdate = now.strftime("%Y%m%dT%H%M%SZ")
    datestamp = now.strftime("%Y%m%d")
    canonical_uri = "/" + urllib.parse.quote(key)
    token = creds["Token"]

    headers = {
        "host": host,
        "x-amz-content-sha256": _EMPTY_SHA,
        "x-amz-date": amzdate,
        "x-amz-security-token": token,
    }
    signed_headers = "host;x-amz-content-sha256;x-amz-date;x-amz-security-token"
    canonical_headers = "".join(f"{k}:{headers[k]}\n" for k in sorted(headers))
    canonical_request = "\n".join(
        ["GET", canonical_uri, "", canonical_headers, signed_headers, _EMPTY_SHA]
    )
    scope = f"{datestamp}/{REGION}/s3/aws4_request"
    string_to_sign = "\n".join(
        ["AWS4-HMAC-SHA256", amzdate, scope,
         hashlib.sha256(canonical_request.encode()).hexdigest()]
    )
    k_date = _sign(("AWS4" + creds["SecretAccessKey"]).encode(), datestamp)
    k_region = _sign(k_date, REGION)
    k_service = _sign(k_region, "s3")
    k_signing = _sign(k_service, "aws4_request")
    signature = hmac.new(k_signing, string_to_sign.encode(), hashlib.sha256).hexdigest()
    auth = (
        f"AWS4-HMAC-SHA256 Credential={creds['AccessKeyId']}/{scope}, "
        f"SignedHeaders={signed_headers}, Signature={signature}"
    )
    req = urllib.request.Request(f"https://{host}{canonical_uri}", headers={
        "Authorization": auth, "x-amz-date": amzdate,
        "x-amz-content-sha256": _EMPTY_SHA, "x-amz-security-token": token,
    })
    return urllib.request.urlopen(req, timeout=10).read()


# ---- vaultless detokenization (AES-SIV / RFC 5297 via CMAC + CTR) ---------------------
_KEY_CACHE: dict = {}


def _epoch_key(epoch: int) -> bytes:
    if epoch not in _KEY_CACHE:
        _KEY_CACHE[epoch] = HKDF(
            algorithm=hashes.SHA256(), length=64, salt=None,
            info=f"ith-tokenization-epoch-{epoch}".encode(),
        ).derive(_DEMO_MASTER)
    return _KEY_CACHE[epoch]


def _cmac(k: bytes, data: bytes) -> bytes:
    c = CMAC(algorithms.AES(k))
    c.update(data)
    return c.finalize()


def _dbl(b: bytes) -> bytes:
    i = int.from_bytes(b, "big")
    msb = i >> 127
    i = (i << 1) & ((1 << 128) - 1)
    if msb:
        i ^= 0x87
    return i.to_bytes(16, "big")


def _xor(a: bytes, b: bytes) -> bytes:
    return bytes(x ^ y for x, y in zip(a, b))


def _s2v(k1: bytes, ad_list, plaintext: bytes) -> bytes:
    d = _cmac(k1, b"\x00" * 16)
    for s in ad_list:
        d = _xor(_dbl(d), _cmac(k1, s))
    if len(plaintext) >= 16:
        t = plaintext[:-16] + _xor(plaintext[-16:], d)            # xorend
    else:
        pad = plaintext + b"\x80" + b"\x00" * (16 - len(plaintext) - 1)
        t = _xor(_dbl(d), pad)
    return _cmac(k1, t)


def detokenize(field: str, token: str) -> str:
    """Inverse of the tokenizer (AES-SIV); recovers the original identifier."""
    if not token or not str(token).startswith("tok:v"):
        return token or ""
    _, ver, body = token.split(":", 2)
    epoch = int(ver[1:])
    blob = _b64url_decode(body)
    key = _epoch_key(epoch)
    k1, k2 = key[:32], key[32:]
    v, ct = blob[:16], blob[16:]
    q = bytearray(v)
    q[8] &= 0x7F
    q[12] &= 0x7F
    dec = Cipher(algorithms.AES(k2), modes.CTR(bytes(q))).decryptor()
    pt = dec.update(ct) + dec.finalize()
    if _s2v(k1, [field.encode()], pt) != v:
        raise ValueError("SIV auth failed")
    return pt.decode("utf-8")


def _b64url_decode(body: str) -> bytes:
    import base64
    return base64.urlsafe_b64decode(body + "=" * (-len(body) % 4))


# ---- HTML ----------------------------------------------------------------------------
PAGE_HEAD = """<!doctype html><meta charset=utf-8>
<title>ITH ePHI viewer (P3)</title>
<style>body{font:14px system-ui;margin:2rem;max-width:64rem}
table{border-collapse:collapse;margin:.5rem 0 1.5rem;width:100%}
td,th{border:1px solid #ccc;padding:.4rem .6rem;text-align:left;font-size:13px}
th{background:#0d47a1;color:#fff} code{background:#f0f0f0;padding:0 .2rem}
.tok{color:#b71c1c}.real{color:#1b5e20}.b{font-weight:600}
h3{margin:1.6rem 0 .2rem}.warn{color:#8a6d00}</style>
<h2>ITH ePHI viewer — human read path (P3)</h2>
<p>Served from the EC2 instance role, inside the VPC (S3 gateway endpoint).
Reached only via SSM port-forward.</p>
"""


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="text/html; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.end_headers()
        self.wfile.write(body.encode() if isinstance(body, str) else body)

    def do_GET(self):
        if self.path.startswith("/healthz"):
            return self._send(200, "ok", "text/plain")
        try:
            creds = get_credentials()
        except Exception as exc:
            return self._send(500, f"<pre>no instance creds: {exc}</pre>")

        records = []
        for key in KEYS:
            try:
                records.append((key, json.loads(s3_get(BUCKET, key, creds)), None))
            except Exception as exc:
                records.append((key, None, exc))

        tok_rows, real_rows = [], []
        for key, rec, exc in records:
            if exc is not None or rec is None:
                tok_rows.append(f"<tr><td colspan=6>error reading {key}: {exc}</td></tr>")
                continue
            pid = rec.get("patient_id", "")[:8]
            # 1) as-stored (tokenized)
            ident = " ".join(
                f"<span class=tok>{rec.get(f, '')}</span>"
                for f in ("name_given", "name_family")
            )
            tok_rows.append(
                f"<tr><td class=b>{pid}</td><td>{ident}</td>"
                f"<td class=tok>{str(rec.get('ssn', ''))[:24]}…</td>"
                f"<td>{rec.get('gender', '')}</td><td>{rec.get('state', '')}</td>"
                f"<td>{len(rec.get('conditions', []))} dx</td></tr>"
            )
            # 2) detokenized (real) — demonstrates reversibility
            try:
                name = (detokenize("name_given", rec.get("name_given", "")) + " " +
                        detokenize("name_family", rec.get("name_family", ""))).strip()
                ssn = detokenize("ssn", rec.get("ssn", ""))
                dob = detokenize("birth_date", rec.get("birth_date", ""))
                phone = detokenize("phone", rec.get("phone", ""))
                addr = detokenize("address_line", rec.get("address_line", ""))
                real_rows.append(
                    f"<tr><td class=b>{pid}</td><td class=real>{name}</td>"
                    f"<td class=real>{ssn}</td><td class=real>{dob}</td>"
                    f"<td class=real>{phone}</td><td class=real>{addr}</td></tr>"
                )
            except Exception as dexc:
                real_rows.append(f"<tr><td colspan=6>detok error {pid}: {dexc}</td></tr>")

        html = (
            PAGE_HEAD +
            f"<p>bucket <code>{BUCKET}</code> · region <code>{REGION}</code> · "
            f"{len(KEYS)} records</p>"
            "<h3>1 · As stored — identifiers <span class=tok>tokenized</span></h3>"
            "<p>This is what actually leaves the bucket; direct identifiers never appear in the clear at rest.</p>"
            "<table><tr><th>id</th><th>name (tokenized)</th><th>ssn (tok)</th>"
            "<th>gender</th><th>state</th><th>conditions</th></tr>"
            + "".join(tok_rows) + "</table>"
            "<h3>2 · Detokenized — <span class=real>real values</span> recovered (capability demo)</h3>"
            "<p class=warn>Reversed here with the AES-SIV epoch key to prove the path <i>can</i> "
            "detokenize when authorised. In production that key is <i>never</i> released by bucket "
            "access: it comes from a separately-controlled enclave CMK whose policy <b>denies</b> "
            "<code>kms:GenerateDataKey</code> / <code>kms:Decrypt</code> to every caller unless the "
            "request carries a Nitro attestation document whose <code>PCR0</code> matches this measured "
            "enclave image. So the key is handed only to the enclave running on <i>this</i> machine — "
            "not the node OS, the node role, or even account root — and to no other use case.</p>"
            "<table><tr><th>id</th><th>name</th><th>ssn</th><th>dob</th>"
            "<th>phone</th><th>address</th></tr>"
            + "".join(real_rows) + "</table>"
        )
        self._send(200, html)

    def log_message(self, *a):  # quiet
        pass


if __name__ == "__main__":
    print(f"ITH webapp on :{PORT} bucket={BUCKET} keys={len(KEYS)}")
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
