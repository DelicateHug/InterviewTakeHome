#!/usr/bin/env python3
"""ITH P5 — code that runs INSIDE the Nitro Enclave.

The enclave has no network and no disk persistence; the only way in/out is a vsock
channel to the parent EC2 instance. For each request the parent sends, this server:

  1. calls `kmstool_enclave_cli` (genkey | decrypt). That tool attaches the enclave's
     *attestation document* (which carries PCR0) to the KMS call. KMS will only honour
     the call if the key policy's kms:RecipientAttestation:PCR0 condition matches — i.e.
     only THIS measured enclave image can obtain/unwrap the data key.
  2. performs AES-256-GCM of the payload IN HERE, so the plaintext data key and the
     plaintext PHI never leave the enclave boundary. Only the wrapped key + ciphertext go
     back out to be stored in S3.

Protocol: 4-byte big-endian length prefix + JSON, both directions.
Request:  {op:"encrypt", key_id, creds:{akid,secret,token,region}, plaintext_b64}
          {op:"decrypt", key_id, creds:{...}, wrapped_dek_b64, nonce_b64, ct_b64}
Response: {ok, ...} or {ok:false, error}
"""
import base64
import json
import os
import socket
import struct
import subprocess
import sys

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

PORT = int(os.environ.get("ENCLAVE_PORT", "5005"))
KMSTOOL = os.environ.get("KMSTOOL", "/kmstool_enclave_cli")
PROXY_PORT = os.environ.get("KMS_PROXY_PORT", "8000")
VMADDR_CID_ANY = getattr(socket, "VMADDR_CID_ANY", 0xFFFFFFFF)


def log(msg):
    sys.stderr.write("[enclave] %s\n" % msg)
    sys.stderr.flush()


def _kmstool(op_args, creds):
    """Run kmstool_enclave_cli and parse its `KEY: value` stdout lines."""
    cmd = [
        KMSTOOL, *op_args,
        "--region", creds["region"],
        "--proxy-port", PROXY_PORT,
        "--aws-access-key-id", creds["akid"],
        "--aws-secret-access-key", creds["secret"],
        "--aws-session-token", creds["token"],
    ]
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError("kmstool %s rc=%s err=%s out=%s"
                           % (op_args[0], p.returncode, p.stderr.strip(), p.stdout.strip()))
    fields = {}
    for line in p.stdout.splitlines():
        if ":" in line:
            k, _, v = line.partition(":")
            fields[k.strip().upper()] = v.strip()
    return fields


def genkey(creds, key_id):
    """GenerateDataKey (attested). Returns (wrapped_dek, plaintext_dek)."""
    f = _kmstool(["genkey", "--key-id", key_id, "--key-spec", "AES-256"], creds)
    return base64.b64decode(f["CIPHERTEXT"]), base64.b64decode(f["PLAINTEXT"])


def decrypt_dek(creds, wrapped):
    """Decrypt the wrapped data key (attested). Returns plaintext_dek."""
    f = _kmstool(["decrypt", "--ciphertext", base64.b64encode(wrapped).decode()], creds)
    return base64.b64decode(f["PLAINTEXT"])


def handle(req):
    op = req.get("op")
    creds = req["creds"]
    if op == "encrypt":
        wrapped, dek = genkey(creds, req["key_id"])
        nonce = os.urandom(12)
        ct = AESGCM(dek).encrypt(nonce, base64.b64decode(req["plaintext_b64"]), None)
        return {
            "ok": True,
            "wrapped_dek_b64": base64.b64encode(wrapped).decode(),
            "nonce_b64": base64.b64encode(nonce).decode(),
            "ct_b64": base64.b64encode(ct).decode(),
        }
    if op == "decrypt":
        dek = decrypt_dek(creds, base64.b64decode(req["wrapped_dek_b64"]))
        pt = AESGCM(dek).decrypt(
            base64.b64decode(req["nonce_b64"]),
            base64.b64decode(req["ct_b64"]),
            None,
        )
        return {"ok": True, "plaintext_b64": base64.b64encode(pt).decode()}
    return {"ok": False, "error": "unknown op %r" % op}


def _recv(conn, n):
    buf = b""
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            raise EOFError("short read")
        buf += chunk
    return buf


def serve():
    s = socket.socket(socket.AF_VSOCK, socket.SOCK_STREAM)
    s.bind((VMADDR_CID_ANY, PORT))
    s.listen(16)
    log("listening on vsock port %d" % PORT)
    while True:
        conn, _ = s.accept()
        try:
            (n,) = struct.unpack(">I", _recv(conn, 4))
            req = json.loads(_recv(conn, n).decode())
            try:
                resp = handle(req)
            except Exception as e:  # never crash the server on a bad request
                log("handler error: %s" % e)
                resp = {"ok": False, "error": str(e)}
            data = json.dumps(resp).encode()
            conn.sendall(struct.pack(">I", len(data)) + data)
        except Exception as e:
            log("conn error: %s" % e)
        finally:
            conn.close()


if __name__ == "__main__":
    serve()
