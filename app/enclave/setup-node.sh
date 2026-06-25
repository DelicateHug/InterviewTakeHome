#!/bin/bash
# ITH P5 — provision the on-prem k8s node as an enclave host.
# Shipped to the node as a file (NOT through Terraform templatefile), so normal bash
# ${VAR} works here. Driven by the thin userdata with real Terraform values as args.
#
# Args: REGION BUCKET S3_ENDPOINT KEY_ALIAS PCR0_PARAM SAMPLE_KEY ACCOUNT_ID
set -xeuo pipefail

REGION="${1:?}"; BUCKET="${2:?}"; S3_ENDPOINT="${3:?}"; KEY_ALIAS="${4:?}"
PCR0_PARAM="${5:?}"; SAMPLE_KEY="${6:?}"; ACCOUNT_ID="${7:?}"
ENCDIR=/opt/ith-enclave
PATIENT="$(basename "$SAMPLE_KEY" .json)"
export HOME=/root
export AWS_DEFAULT_REGION="$REGION"

echo "=== [1/8] packages ==="
dnf install -y docker git unzip python3 python3-pip \
  aws-nitro-enclaves-cli aws-nitro-enclaves-cli-devel
# AWS CLI v2 (host needs it for ssm put-parameter + kubectl configmap from outputs)
if ! command -v aws >/dev/null 2>&1; then
  curl -s https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscliv2.zip
  ( cd /tmp && unzip -q -o awscliv2.zip && ./aws/install --update )
fi
export PATH=/usr/local/bin:$PATH

echo "=== [2/8] docker + nitro allocator ==="
systemctl enable --now docker
# dedicate 2 vCPU / 2048 MiB to the enclave
cat >/etc/nitro_enclaves/allocator.yaml <<EOF
---
memory_mib: 2048
cpu_count: 2
EOF
systemctl enable --now nitro-enclaves-allocator.service

echo "=== [3/8] vsock-proxy (enclave -> KMS) ==="
# Ensure our regional KMS endpoint is allow-listed for the proxy.
grep -q "kms.${REGION}.amazonaws.com" /etc/nitro_enclaves/vsock-proxy.yaml 2>/dev/null \
  || cat >>/etc/nitro_enclaves/vsock-proxy.yaml <<EOF
- {address: kms.${REGION}.amazonaws.com, port: 443}
EOF
cat >/etc/systemd/system/ith-vsock-proxy.service <<EOF
[Unit]
Description=ITH vsock-proxy enclave->KMS
After=nitro-enclaves-allocator.service
[Service]
ExecStart=/usr/bin/vsock-proxy 8000 kms.${REGION}.amazonaws.com 443 --config /etc/nitro_enclaves/vsock-proxy.yaml
Restart=always
[Install]
WantedBy=multi-user.target
EOF

echo "=== [4/8] build enclave image + capture PCR0 -> SSM ==="
chmod +x "$ENCDIR/build-enclave.sh"
"$ENCDIR/build-enclave.sh" "$REGION" "$PCR0_PARAM"
PCR0="$(cat "$ENCDIR/pcr0.txt")"

echo "=== [5/8] run enclave + broker (systemd) ==="
cat >/etc/systemd/system/ith-enclave.service <<EOF
[Unit]
Description=ITH Nitro Enclave (production mode = real PCR attestation)
After=nitro-enclaves-allocator.service
Requires=nitro-enclaves-allocator.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/nitro-cli run-enclave --eif-path ${ENCDIR}/ith.eif --cpu-count 2 --memory 2048 --enclave-cid 16 --enclave-name ith
ExecStop=/usr/bin/nitro-cli terminate-enclave --all
[Install]
WantedBy=multi-user.target
EOF
cat >/etc/systemd/system/ith-broker.service <<EOF
[Unit]
Description=ITH enclave host broker (pod <-> enclave bridge)
After=ith-enclave.service ith-vsock-proxy.service
Requires=ith-enclave.service
[Service]
Environment=ENCLAVE_KEY_ID=${KEY_ALIAS}
Environment=AWS_REGION=${REGION}
Environment=ENCLAVE_CID=16
Environment=ENCLAVE_PORT=5005
Environment=BROKER_PORT=7070
ExecStart=/usr/bin/python3 ${ENCDIR}/host_broker.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now ith-vsock-proxy.service
systemctl enable --now ith-enclave.service
systemctl enable --now ith-broker.service

echo "=== [6/8] k3s ==="
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --disable servicelb" sh -
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
for i in $(seq 1 40); do
  /usr/local/bin/kubectl get nodes 2>/dev/null | grep -q " Ready" && break
  sleep 5
done
# the master/control-plane node must actually schedule pods (the ask: "uncordon itself")
/usr/local/bin/kubectl uncordon "$(hostname)" 2>/dev/null || true
/usr/local/bin/kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true
/usr/local/bin/kubectl taint nodes --all node-role.kubernetes.io/master- 2>/dev/null || true

echo "=== [7/8] P2 read CronJob (unchanged) + P5 config ==="
cat >/root/phi-reader.yaml <<EOF
apiVersion: batch/v1
kind: CronJob
metadata:
  name: phi-reader
spec:
  schedule: "*/5 * * * *"
  jobTemplate:
    spec:
      backoffLimit: 1
      template:
        spec:
          hostNetwork: true
          restartPolicy: Never
          containers:
          - name: awscli
            image: public.ecr.aws/aws-cli/aws-cli:latest
            command: ["/bin/sh","-c"]
            args:
              - >
                aws s3api get-object --bucket ${BUCKET} --key ${SAMPLE_KEY}
                --endpoint-url https://${S3_ENDPOINT} --region ${REGION} /tmp/o
                && echo "READ_OK \$(wc -c </tmp/o) bytes via ${S3_ENDPOINT}"
EOF
/usr/local/bin/kubectl apply -f /root/phi-reader.yaml
/usr/local/bin/kubectl create configmap enclave-cfg \
  --from-literal=BUCKET="$BUCKET" \
  --from-literal=REGION="$REGION" \
  --from-literal=S3_ENDPOINT="$S3_ENDPOINT" \
  --from-literal=PATIENT="$PATIENT" \
  --from-literal=BROKER="http://127.0.0.1:7070" \
  --dry-run=client -o yaml | /usr/local/bin/kubectl apply -f -

echo "=== [8/8] wait for broker, then run the P5 read/write Job ==="
for i in $(seq 1 30); do
  curl -sf http://127.0.0.1:7070/healthz >/dev/null 2>&1 && break
  sleep 5
done
/usr/local/bin/kubectl delete job phi-rw-enclave --ignore-not-found
/usr/local/bin/kubectl apply -f "$ENCDIR/phi-rw-enclave.yaml"
echo "DONE setup-node.sh (PCR0=$PCR0)"
