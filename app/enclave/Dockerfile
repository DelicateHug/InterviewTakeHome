# ITH P5 — the ENCLAVE image. nitro-cli turns this into an EIF; its measured hash is PCR0.
#
# The SDK's `kmstool-enclave-cli` image is a STRIPPED Amazon Linux 2 rootfs: it has the
# `/kmstool_enclave_cli` binary (which does the attested KMS calls) + `libnsm.so`, but no
# package manager and no python. So we build on a FULL amazonlinux:2 base (same glibc the
# binary was linked against), add python3 + AES-GCM, and COPY just the binary + libnsm.so.
# Keep this minimal & deterministic so PCR0 is stable across rebuilds of the same inputs.
ARG KMSTOOL_IMG=kmstool-enclave-cli:latest
FROM ${KMSTOOL_IMG} AS kmstool

FROM amazonlinux:2
RUN yum install -y python3 python3-pip \
 && python3 -m pip install --upgrade pip \
 && python3 -m pip install --no-cache-dir "cryptography<42" \
 && yum clean all && rm -rf /var/cache/yum

# the attested-KMS CLI + its only non-standard shared lib, lifted from the SDK image
COPY --from=kmstool /kmstool_enclave_cli /kmstool_enclave_cli
COPY --from=kmstool /lib64/libnsm.so /lib64/libnsm.so

COPY enclave_server.py /enclave_server.py
ENV ENCLAVE_PORT=5005 \
    KMS_PROXY_PORT=8000 \
    KMSTOOL=/kmstool_enclave_cli
CMD ["python3", "/enclave_server.py"]
