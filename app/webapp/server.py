#!/usr/bin/env python3
"""
EC2 web app — the SOLE human read path (P3, C1).

Humans reach this only via SSM Session Manager port-forwarding (no SSH, no public
ingress). The app reads the SENSITIVE bucket using the EC2 *instance role* from inside
the VPC (S3 gateway endpoint -> aws:sourceVpce satisfied). It is written in the Python
*standard library only* (no pip, no boto3) — including a hand-rolled SigV4 signer — so it
runs on the no-internet workload host with nothing to install.

Identifiers remain TOKENIZED in what the app displays: even the human read path never
shows raw PHI (detokenization needs the separately-controlled epoch key). Defense in depth.

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

REGION = os.environ.get("ITH_REGION", "ap-southeast-1")
BUCKET = os.environ["ITH_BUCKET"]
KEYS = [k for k in os.environ.get("ITH_KEYS", "").split(",") if k]
PORT = int(os.environ.get("ITH_PORT", "8080"))

_IMDS = "http://169.254.169.254"
_EMPTY_SHA = hashlib.sha256(b"").hexdigest()


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


# ---- HTTP handler --------------------------------------------------------------------
PAGE_HEAD = """<!doctype html><meta charset=utf-8>
<title>ITH ePHI viewer (P3)</title>
<style>body{font:14px system-ui;margin:2rem;max-width:60rem}
table{border-collapse:collapse;margin:1rem 0;width:100%}
td,th{border:1px solid #ccc;padding:.4rem .6rem;text-align:left;font-size:13px}
th{background:#0d47a1;color:#fff} code{background:#f0f0f0;padding:0 .2rem}
.tok{color:#b71c1c}.b{font-weight:600}</style>
<h2>ITH ePHI viewer — human read path (P3)</h2>
<p>Served from the EC2 instance role, inside the VPC (S3 gateway endpoint).
Reached only via SSM port-forward. Direct identifiers stay <span class=tok>tokenized</span>.</p>
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

        rows = []
        for key in KEYS:
            try:
                rec = json.loads(s3_get(BUCKET, key, creds))
                ident = " ".join(
                    f"<span class=tok>{rec.get(f, '')}</span>"
                    for f in ("name_given", "name_family")
                )
                rows.append(
                    f"<tr><td class=b>{rec.get('patient_id', '')[:8]}</td>"
                    f"<td>{ident}</td><td class=tok>{rec.get('ssn', '')[:24]}…</td>"
                    f"<td>{rec.get('gender', '')}</td><td>{rec.get('state', '')}</td>"
                    f"<td>{len(rec.get('conditions', []))} dx</td></tr>"
                )
            except Exception as exc:
                rows.append(f"<tr><td colspan=6>error reading {key}: {exc}</td></tr>")

        html = (PAGE_HEAD +
                f"<p>bucket <code>{BUCKET}</code> · region <code>{REGION}</code> · "
                f"{len(KEYS)} records</p>"
                "<table><tr><th>id</th><th>name (tokenized)</th><th>ssn (tok)</th>"
                "<th>gender</th><th>state</th><th>conditions</th></tr>"
                + "".join(rows) + "</table>")
        self._send(200, html)

    def log_message(self, *a):  # quiet
        pass


if __name__ == "__main__":
    print(f"ITH webapp on :{PORT} bucket={BUCKET} keys={len(KEYS)}")
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
