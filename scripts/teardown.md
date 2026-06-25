# Teardown runbook (run after verdict)

Everything is isolated in the new member account `118821711925` under the OU
`InterviewTakeHome`, so teardown is contained. Use the helper or the manual steps.

## One-shot
```powershell
pwsh scripts/teardown.ps1
```
It (1) empties the versioned PHI buckets, then destroys (2) `20-workload`,
(3) `10-identity`, (4) `00-org` — the last step **closes the member account**.

## Manual order (if you prefer)
```bash
# 1) empty versioned buckets (terraform won't delete non-empty buckets)
#    sensitive + deident: delete all versions & delete-markers (see teardown.ps1)

# 2) workload resources in the member account
cd terraform/20-workload && terraform destroy

# 3) Identity Center permission sets (mgmt account)
cd ../10-identity && terraform destroy

# 4) OU + SCP + RCP + CLOSE the member account
cd ../00-org && terraform destroy
```

## Important caveats
- **Account closure is not instant.** `close_on_deletion = true` puts the account in
  **SUSPENDED** state for **~90 days** before AWS fully deletes it; the root email
  (`dylanheathsmart+ith-workload@gmail.com`) **cannot be reused** until then.
- **KMS keys** linger for the 7-day deletion window (`deletion_window_in_days = 7`);
  they stop being usable immediately on schedule-deletion.
- **CloudTrail bucket** has `force_destroy = true`; the PHI buckets do **not** (so they
  can't be wiped accidentally) — that's why step 1 empties them explicitly.
- If a `destroy` is blocked by the SCP/RCP (e.g. an S3 delete), detach the policies from
  the OU first: `aws organizations detach-policy --policy-id p-kt4wutiz --target-id ou-33e3-5p8xygxw`
  (and `p-02p8l548gj`), then re-run.
- The live Entra tenant was **never modified** (Entra resources were disabled), so there
  is nothing to clean up there.
