<#
  Uploads the tokenized Synthea dataset to S3 AFTER 20-workload is applied.
    - sensitive records -> phi-sensitive-<acct>, each under its PER-PATIENT KMS CMK (R15)
    - de-identified records -> phi-deident-<acct>, under the shared deident CMK
  Every PutObject sends `--sse aws:kms` (the org SCP denies PHI puts without it) over TLS.
  Run from anywhere; uses the ith-workload profile (assumes into the member account).
#>
$ErrorActionPreference = "Stop"
$profile = "ith-workload"
$region  = "ap-southeast-1"
$root    = Split-Path -Parent $PSScriptRoot

$acct = (aws sts get-caller-identity --profile $profile --query Account --output text)
$sens = "phi-sensitive-$acct"
$deid = "phi-deident-$acct"
Write-Output "account=$acct  sensitive=$sens  deident=$deid"

$index = Get-Content "$root\data\patient-index.json" -Raw | ConvertFrom-Json
foreach ($p in $index.patients) {
  $key = "patients/$($p.patient_id).json"

  aws s3api put-object --bucket $sens --key $key `
    --body "$root\data\patients-sensitive\$($p.patient_id).json" `
    --server-side-encryption aws:kms --ssekms-key-id "alias/ith/patient/$($p.key_id)" `
    --content-type application/json --profile $profile --region $region | Out-Null

  aws s3api put-object --bucket $deid --key $key `
    --body "$root\data\patients-deident\$($p.patient_id).json" `
    --server-side-encryption aws:kms --ssekms-key-id "alias/ith/deident" `
    --content-type application/json --profile $profile --region $region | Out-Null

  Write-Output "uploaded $($p.patient_id)  (per-patient key alias/ith/patient/$($p.key_id))"
}
Write-Output "DONE: $($index.patients.Count) patients -> sensitive + deident"
