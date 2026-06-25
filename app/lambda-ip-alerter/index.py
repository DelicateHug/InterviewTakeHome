"""
R12 — IP-based alerting on role assumptions.

Triggered by EventBridge on every sts:AssumeRole / AssumeRoleWithSAML (via CloudTrail).
Publishes to SNS when the source IP is a real, external IP that is NOT in the configured
allow-list. AWS-service callers (hostname source) are ignored.

ALLOWED_CIDRS empty (the demo default) => every external IP alerts, so the control is
demonstrably firing; in production set it to your admin egress ranges.
"""
import ipaddress
import json
import os

import boto3

_SNS = boto3.client("sns")
TOPIC = os.environ["SNS_TOPIC"]
_ALLOWED = [c.strip() for c in os.environ.get("ALLOWED_CIDRS", "").split(",") if c.strip()]
_NETS = [ipaddress.ip_network(c) for c in _ALLOWED]


def handler(event, context):
    d = event.get("detail", {}) or {}
    ip = d.get("sourceIPAddress", "")
    name = d.get("eventName", "")
    who = (d.get("userIdentity") or {}).get("arn", "?")

    if ip.endswith("amazonaws.com"):
        return {"skipped": "aws-service-caller"}
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return {"skipped": "no-ip"}

    if any(addr in n for n in _NETS):
        return {"ok": "allowed-ip", "ip": ip}

    msg = (
        "[ITH SECURITY ALERT] Role assumption from an unexpected source IP\n\n"
        f"  eventName  : {name}\n"
        f"  sourceIP   : {ip}\n"
        f"  principal  : {who}\n"
        f"  allowed    : {_ALLOWED or '(none configured -> all external IPs alert)'}\n"
    )
    _SNS.publish(TopicArn=TOPIC, Subject="ITH: AssumeRole from unexpected IP", Message=msg)
    return {"alerted": ip, "event": name}
