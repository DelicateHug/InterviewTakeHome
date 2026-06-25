<#
  Full teardown. Destroys in reverse dependency order. The new member account is CLOSED
  by destroying 00-org (close_on_deletion = true). NOTE: AWS account closure puts the
  account in SUSPENDED state for ~90 days before final deletion, and the email cannot be
  reused until then. See teardown.md for the manual fallbacks.
#>
$ErrorActionPreference = "Stop"
$wprofile = "ith-workload"
$region   = "ap-southeast-1"
$tf       = Split-Path -Parent $PSScriptRoot | Join-Path -ChildPath "terraform"

# 1) Empty the versioned PHI buckets (terraform won't delete non-empty buckets).
$acct = (aws sts get-caller-identity --profile $wprofile --query Account --output text)
foreach ($b in @("phi-sensitive-$acct", "phi-deident-$acct")) {
  Write-Output "emptying $b (all versions)..."
  $vs = aws s3api list-object-versions --bucket $b --profile $wprofile --region $region --output json 2>$null | ConvertFrom-Json
  foreach ($coll in @($vs.Versions, $vs.DeleteMarkers)) {
    foreach ($o in $coll) {
      if ($o) { aws s3api delete-object --bucket $b --key $o.Key --version-id $o.VersionId --profile $wprofile --region $region | Out-Null }
    }
  }
}

# 2) Destroy workload (member account), 3) identity (permission sets), 4) org (closes account)
foreach ($stack in @("20-workload", "10-identity", "00-org")) {
  Write-Output "=== terraform destroy $stack ==="
  Push-Location (Join-Path $tf $stack)
  terraform destroy -auto-approve -no-color
  Pop-Location
}
Write-Output "Teardown complete. The member account is now SUSPENDED (90-day window)."
