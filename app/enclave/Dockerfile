# ITH P5 — the ENCLAVE image. nitro-cli turns this into an EIF; its measured hash is PCR0.
#
# Built ON TOP of the AWS SDK's `kmstool-enclave-cli` image, which provides the
# `/kmstool_enclave_cli` binary (+ its shared libs) that does the attested KMS calls.
# We add a small Python server (enclave_server.py) that drives the CLI and does the
# AES-256-GCM envelope INSIDE the enclave. Keep this image minimal & deterministic so
# PCR0 is stable across rebuilds of the same inputs.
ARG BASE=kmstool-enclave-cli:latest
FROM ${BASE}

# python3 + AES-GCM (cryptography) for the in-enclave envelope. dnf on AL2023, yum on AL2.
RUN (command -v dnf >/dev/null 2>&1 && dnf install -y python3 python3-pip) \
 || (yum install -y python3 python3-pip) \
 && python3 -m pip install --no-cache-dir cryptography \
 && (dnf clean all 2>/dev/null || yum clean all 2>/dev/null || true)

COPY enclave_server.py /enclave_server.py

ENV ENCLAVE_PORT=5005 \
    KMS_PROXY_PORT=8000 \
    KMSTOOL=/kmstool_enclave_cli

CMD ["python3", "/enclave_server.py"]
