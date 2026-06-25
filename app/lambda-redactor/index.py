"""
The Lambda "basic reader" (P1, C2).

Intended design was an S3 Object Lambda Access Point. AWS now gates S3 Object Lambda to
"existing customers" only, so a brand-new account gets AccessDenied on create. We use the
supported equivalent: a Lambda (exposed via an IAM-auth Function URL) that reads the
sensitive record THROUGH a standard S3 ACCESS POINT and returns ONLY non-sensitive fields.
The raw record never leaves the Lambda; the caller only ever sees de-identified data.

Invoke (IAM-signed): GET <function-url>?key=patients/<patient-id>.json
"""
import json
import os

import boto3

_S3 = boto3.client("s3")
AP_ARN = os.environ["AP_ARN"]  # standard S3 access point ARN (reads the VPC-locked bucket)

# Direct/indirect identifiers -> never returned by the basic reader.
_DROP = {
    "name_given", "name_family", "ssn", "mrn", "phone", "email",
    "address_line", "postal_code", "birth_date", "city", "patient_id", "token_epoch",
}


def handler(event, context):
    qs = (event or {}).get("queryStringParameters") or {}
    key = qs.get("key") or (event or {}).get("key")
    if not key:
        return {"statusCode": 400,
                "body": json.dumps({"error": "missing ?key=patients/<patient-id>.json"})}
    try:
        obj = _S3.get_object(Bucket=AP_ARN, Key=key)
        rec = json.loads(obj["Body"].read())
    except Exception as exc:
        return {"statusCode": 502, "body": json.dumps({"error": str(exc)[:200]})}

    redacted = {k: v for k, v in rec.items() if k not in _DROP}
    redacted["schema"] = "ith.patient.deident/v1"
    redacted["_redacted_by"] = "lambda:ith-redactor (basic reader)"
    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(redacted, indent=2),
    }
