<#
.SYNOPSIS
  ITH P5 — two-phase deploy of the attested Nitro Enclave read/write path.

  The enclave KMS key [43] must be locked to the enclave image's PCR0, but PCR0 is only
  known after the node builds the EIF. So:

    Phase A  terraform apply (enclave_pcr0="")  -> replaces the node as an enclave host,
             which builds the EIF and publishes PCR0 to SSM /ith/enclave/pcr0.
    (wait)   poll SSM until the node has published PCR0 (the build takes ~10-20 min:
             it compiles the AWS Nitro Enclaves C SDK on first boot).
    Phase B  terraform apply -var enclave_pcr0=<that value> -> the key now grants
             Decrypt/GenerateDataKey ONLY to that measured enclave.

  Re-run any time; capture-then-lock is idempotent. Rebuild the enclave -> PCR0 changes
  -> just re-run Phase B with the new value.

.NOTES
  Terraform itself uses the ith-mgmt profile (assumes into the workload acct). SSM reads
  here use the ith-workload profile directly.
#>
[CmdletBinding()]
param(
  [string]$Region      = "ap-southeast-1",
  [string]$Profile     = "ith-workload",
  [string]$Pcr0Param   = "/ith/enclave/pcr0",
  [int]   $WaitMinutes = 30
)
$ErrorActionPreference = "Stop"
$tf = Join-Path $PSScriptRoot "..\terraform\20-workload"

Write-Host "== Phase A: apply (node rebuilds as enclave host, key root-only) ==" -ForegroundColor Cyan
terraform -chdir="$tf" apply -auto-approve -var "enclave_pcr0="

Write-Host "== Waiting for the node to publish PCR0 to SSM $Pcr0Param ==" -ForegroundColor Cyan
$deadline = (Get-Date).AddMinutes($WaitMinutes)
$pcr0 = $null
while ((Get-Date) -lt $deadline) {
  try {
    $pcr0 = aws ssm get-parameter --name $Pcr0Param --query "Parameter.Value" --output text `
              --profile $Profile --region $Region 2>$null
  } catch { $pcr0 = $null }
  if ($pcr0 -and $pcr0 -ne "None" -and $pcr0.Trim().Length -gt 0) { break }
  Write-Host ("  ...still building EIF on the node ({0:HH:mm:ss})" -f (Get-Date))
  Start-Sleep -Seconds 30
}
if (-not $pcr0 -or $pcr0 -eq "None") { throw "PCR0 not published within $WaitMinutes min. Check /var/log/ith-setup.log on the node via SSM." }
$pcr0 = $pcr0.Trim()
Write-Host "PCR0 = $pcr0" -ForegroundColor Green

Write-Host "== Phase B: apply with the captured PCR0 (lock the key) ==" -ForegroundColor Cyan
terraform -chdir="$tf" apply -auto-approve -var "enclave_pcr0=$pcr0"

Write-Host "`nDone. Verify:" -ForegroundColor Green
terraform -chdir="$tf" output -raw enclave_demo_hint
