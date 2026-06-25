"""
S3 Object Lambda — the "basic reader" (P1, C2).

Invoked by the Object Lambda Access Point. It fetches the ORIGINAL sensitive record
(via the presigned inputS3Url to the supporting access point), strips every direct
identifier, and returns ONLY non-sensitive fields. The caller of the access point
therefore can never see PHI — the transform happens server-side inside the Lambda.
"""
import json
import urllib.request

import boto3

_S3 = boto3.client("s3")

# Fields that are direct/indirect identifiers -> never returned by the basic reader.
_DROP = {
    "name_given", "name_family", "ssn", "mrn", "phone", "email",
    "address_line", "postal_code", "birth_date", "city", "patient_id", "token_epoch",
}


def handler(event, context):
    ctx = event["getObjectContext"]
    route = ctx["outputRoute"]
    token = ctx["outputToken"]
    url = ctx["inputS3Url"]

    try:
        raw = urllib.request.urlopen(url, timeout=10).read()
        rec = json.loads(raw)
    except Exception as exc:  # surface a clean error to the caller
        _S3.write_get_object_response(
            RequestRoute=route, RequestToken=token, StatusCode=502,
            ErrorCode="RedactorFetchFailed", ErrorMessage=str(exc)[:200],
        )
        return {"statusCode": 502}

    redacted = {k: v for k, v in rec.items() if k not in _DROP}
    redacted["schema"] = "ith.patient.deident/v1"
    redacted["_redacted_by"] = "object-lambda:ith-redactor"

    _S3.write_get_object_response(
        RequestRoute=route,
        RequestToken=token,
        Body=json.dumps(redacted, indent=2).encode("utf-8"),
        ContentType="application/json",
    )
    return {"statusCode": 200}
