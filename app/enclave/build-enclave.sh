#!/bin/bash
# ITH P5 — build the enclave image (EIF), capture its PCR0, publish PCR0 to SSM.
# Idempotent: safe to re-run via SSM while iterating. Args: <region> <ssm_pcr0_param>
set -xeuo pipefail

REGION="${1:?usage: build-enclave.sh <region> <ssm_pcr0_param>}"
PCR0_PARAM="${2:?usage: build-enclave.sh <region> <ssm_pcr0_param>}"
ENCDIR="${ENCDIR:-/opt/ith-enclave}"
SDK="${SDK:-/opt/aws-nitro-enclaves-sdk-c}"

# 1) Build the SDK's kmstool-enclave-cli image (provides /kmstool_enclave_cli + libs).
if ! docker image inspect kmstool-enclave-cli:latest >/dev/null 2>&1; then
  rm -rf "$SDK"
  git clone --depth 1 https://github.com/aws/aws-nitro-enclaves-sdk-c.git "$SDK"
  cd "$SDK"
  # Dockerfile/target names have drifted across SDK versions — try the known variants.
  docker build --target kmstool-enclave-cli -t kmstool-enclave-cli:latest -f containers/Dockerfile.al2023 . \
   || docker build --target kmstool-enclave-cli -t kmstool-enclave-cli:latest -f containers/Dockerfile.al2 . \
   || docker build --target kmstool-enclave-cli -t kmstool-enclave-cli:latest -f containers/Dockerfile .
fi

# 2) Build our enclave image on top of it.
cd "$ENCDIR"
docker build -t ith-enclave:latest .

# 3) Build the EIF and capture PCR0 from the measurements JSON.
nitro-cli build-enclave --docker-uri ith-enclave:latest --output-file "$ENCDIR/ith.eif" \
  | tee "$ENCDIR/measurements.json"
PCR0="$(python3 -c "import json,sys;print(json.load(open('$ENCDIR/measurements.json'))['Measurements']['PCR0'])")"
echo "$PCR0" > "$ENCDIR/pcr0.txt"
echo "PCR0=$PCR0"

# 4) Publish PCR0 so the 2nd terraform apply can lock the KMS key to it.
aws ssm put-parameter --region "$REGION" --name "$PCR0_PARAM" \
  --type String --overwrite --value "$PCR0"
echo "published PCR0 to SSM $PCR0_PARAM"
