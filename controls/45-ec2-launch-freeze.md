# [45] EC2 launch freeze SCP

**Type:** Service Control Policy

> **In plain terms —** The demo's two EC2 instances are already up, and the demo never needs more compute. So this SCP denies *launching* new instances for everyone — even SuperAdmin — leaving a reviewer no way to spin up extra boxes to run code or pivot. The instances we already have keep running; only *creating more* is blocked.

## Controls applied

- **Prevention:** The `ith-scp-no-new-ec2` SCP (00-org) **Denies** every EC2 launch path — `ec2:RunInstances`, `ec2:RunScheduledInstances`, `ec2:CreateFleet`, `ec2:RequestSpotInstances`, `ec2:RequestSpotFleet` — for every principal in the account *except* the IaC break-glass role (`OrganizationAccountAccessRole`, via `var.ec2_launch_admin_principal_arns`). Deny wins over the allow-list SCP [[41]](41-account-scp.md)'s `ec2:*` grant, so it caps even SuperAdmin. `ec2:StartInstances` is **not** denied, so the already-provisioned nodes [[28]](28-ec2-webapp.md) [[30]](30-onprem-node.md) can still be stopped/started for cost.
- **Detection:** Org CloudTrail on the denied `RunInstances` call → unauthorized-api alarm [[35]](35-alarms.md).
- **Alert:** Denied launch → SNS [[36]](36-sns.md); the SCP being edited/detached → change-alerter [[40]](40-change-alerter.md).

## What would trigger an alert

- Any principal — even SuperAdmin — calls `RunInstances` (console "Launch instance", Spot, or a fleet) → denied → unauthorized-api alarm [[35]](35-alarms.md) → SNS [[36]](36-sns.md).
- The SCP is edited or detached (an attempt to re-open EC2 creation) → org CloudTrail → change-alerter [[40]](40-change-alerter.md).

> **Why launch, not start —** "Create more" is `RunInstances` and its Spot/Fleet siblings; `StartInstances` only powers a *stopped, already-approved* instance back on. Denying launch freezes the fleet at its deployed size while leaving normal stop/start cost management intact. Break-glass to genuinely add an instance stays available from the management account via `OrganizationAccountAccessRole`.

---
[< controls index](README.md) | [< home](../README.md)
