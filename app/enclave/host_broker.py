#!/usr/bin/env python3
"""ITH P5 — host-side broker (runs on the PARENT EC2 instance, as a systemd service).

The enclave has no network, so it cannot fetch credentials or talk to the k8s pod
directly. This broker is the bridge:

  k8s pod  --HTTP-->  broker (127.0.0.1:7070)  --vsock-->  enclave  --vsock-proxy-->  KMS

For each request it pulls the *node instance-role* credentials from IMDSv2 and forwards
them to the enclave (the enclave needs creds to sign the KMS call; the attestation
document is what actually authorises it). It deliberately exposes only encrypt/decrypt —
the broker itself never sees a plaintext data key.
"""
import base64
import json
import os
import socket
import struct
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

ENCLAVE_CID = int(os.environ.get("ENCLAVE_CID", "16"))
ENCLAVE_PORT = int(os.environ.get("ENCLAVE_PORT", "5005"))
KEY_ID = os.environ.get("ENCLAVE_KEY_ID", "alias/ith/enclave")
REGION = os.environ.get("AWS_REGION") or os.environ.get("REGION", "ap-southeast-1")
BIND = ("127.0.0.1", int(os.environ.get("BROKER_PORT", "7070")))
IMDS = "http://169.254.169.254"


def imds_creds():
    tok = urllib.request.urlopen(urllib.request.Request(
        IMDS + "/latest/api/token", method="PUT",
        headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"}), timeout=2).read().decode()
    h = {"X-aws-ec2-metadata-token": tok}
    role = urllib.request.urlopen(urllib.request.Request(
        IMDS + "/latest/meta-data/iam/security-credentials/", headers=h), timeout=2).read().decode().strip()
    j = json.loads(urllib.request.urlopen(urllib.request.Request(
        IMDS + "/latest/meta-data/iam/security-credentials/" + role, headers=h), timeout=2).read().decode())
    return {"akid": j["AccessKeyId"], "secret": j["SecretAccessKey"],
            "token": j["Token"], "region": REGION}


def _recv(s, n):
    buf = b""
    while len(buf) < n:
        c = s.recv(n - len(buf))
        if not c:
            raise EOFError("short read")
        buf += c
    return buf


def call_enclave(req):
    s = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
    s.settimeout(20)
    try:
        s.connect((ENCLAVE_CID, ENCLAVE_PORT))
        data = json.dumps(req).encode()
        s.sendall(struct.pack(">I", len(data)) + data)
        (n,) = struct.unpack(">I", _recv(s, 4))
        return json.loads(_recv(s, n).decode())
    finally:
        s.close()


class Handler(BaseHTTPRequestHandler):
    def _reply(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path == "/healthz":
            return self._reply(200, {"ok": True, "cid": ENCLAVE_CID, "key_id": KEY_ID})
        self._reply(404, {"ok": False, "error": "not found"})

    def do_POST(self):
        op = {"/encrypt": "encrypt", "/decrypt": "decrypt"}.get(self.path)
        if not op:
            return self._reply(404, {"ok": False, "error": "bad path"})
        n = int(self.headers.get("Content-Length", "0"))
        body = json.loads(self.rfile.read(n) or b"{}")
        req = {"op": op, "key_id": KEY_ID, "creds": imds_creds()}
        req.update(body)
        try:
            self._reply(200, call_enclave(req))
        except Exception as e:
            self._reply(502, {"ok": False, "error": str(e)})

    def log_message(self, *a):  # quiet
        pass


if __name__ == "__main__":
    HTTPServer(BIND, Handler).serve_forever()
