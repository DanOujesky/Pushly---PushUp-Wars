#!/usr/bin/env python3
"""Throw-away Apple Development certificate for one CI run (ios-testflight.yml, D-042).

Hosted macOS runners are fresh machines: Xcode's automatic signing needs a development identity *with its private
key* in the keychain to create profiles and archive. This script makes one through the App Store Connect API with a
key generated on the runner, writes a PKCS#12 for `security import`, and revokes it again at the end of the run — so
no certificate or private key is ever stored anywhere (distribution signing on export is cloud-managed by Apple).

    asc_dev_cert.py create <outdir>   # → outdir/dev.p12, outdir/password, outdir/cert_id
    asc_dev_cert.py revoke <cert_id>
Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (the .p8 text).
"""
import base64
import json
import os
import secrets
import sys
import time
import urllib.request

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

API = "https://api.appstoreconnect.apple.com/v1"


def token() -> str:
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                      os.environ["ASC_KEY_P8"], algorithm="ES256",
                      headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method: str, path: str, body: dict | None = None) -> dict:
    req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as res:
            raw = res.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        sys.exit(f"App Store Connect API {method} {path} failed: {e.code} {e.read().decode()[:500]}")


def create(outdir: str) -> None:
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (x509.CertificateSigningRequestBuilder()
           .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Pushly CI"),
                                    x509.NameAttribute(NameOID.COUNTRY_NAME, "CZ")]))
           .sign(key, hashes.SHA256()))
    pem = csr.public_bytes(serialization.Encoding.PEM).decode()
    res = call("POST", "/certificates", {"data": {"type": "certificates", "attributes": {
        "csrContent": pem, "certificateType": "DEVELOPMENT"}}})
    cert_id = res["data"]["id"]
    cert = x509.load_der_x509_certificate(base64.b64decode(res["data"]["attributes"]["certificateContent"]))
    password = secrets.token_urlsafe(24)
    # Legacy PKCS#12 encryption (3DES / SHA1) — what macOS `security import` reliably accepts.
    enc = (serialization.PrivateFormat.PKCS12.encryption_builder().kdf_rounds(50000)
           .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC).hmac_hash(hashes.SHA1())
           .build(password.encode()))
    p12 = pkcs12.serialize_key_and_certificates(b"Pushly CI", key, cert, None, enc)
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "dev.p12"), "wb") as f:
        f.write(p12)
    with open(os.path.join(outdir, "password"), "w") as f:
        f.write(password)
    with open(os.path.join(outdir, "cert_id"), "w") as f:
        f.write(cert_id)
    print(f"created development certificate {cert_id}")


def revoke(cert_id: str) -> None:
    call("DELETE", f"/certificates/{cert_id}")
    print(f"revoked {cert_id}")


def diagnose(_: str = "") -> None:
    """Prints what this key can see (role check: /users needs Admin) — for signing troubleshooting."""
    apps = call("GET", "/apps?filter[bundleId]=app.pushly")["data"]
    if apps:
        app_id = apps[0]["id"]
        builds = call("GET", f"/builds?filter[app]={app_id}&limit=20")["data"]
        print(f"BUILDS: {len(builds)}")
        for b in sorted(builds, key=lambda x: x["attributes"].get("uploadedDate") or "", reverse=True)[:8]:
            a = b["attributes"]
            print(f"BUILD {a.get('version')} uploaded={a.get('uploadedDate')} state={a.get('processingState')} "
                  f"expired={a.get('expired')} encryption={a.get('usesNonExemptEncryption')} minOs={a.get('minOsVersion')}")
            det = call("GET", f"/builds/{b['id']}/buildBetaDetail")["data"]["attributes"]
            print(f"  beta internal={det.get('internalBuildState')} external={det.get('externalBuildState')}")
        for t in call("GET", f"/betaTesters?filter[apps]={app_id}&limit=10")["data"]:
            a = t["attributes"]
            print(f"TESTER {a.get('email')} state={a.get('state')} invite={a.get('inviteType')}")
    for path in ["/apps?filter[bundleId]=app.pushly", "/bundleIds?limit=20", "/certificates?limit=20", "/profiles?limit=20",
                 "/devices?limit=5", "/users?limit=1"]:
        req = urllib.request.Request(API + path, headers={"Authorization": f"Bearer {token()}"})
        try:
            with urllib.request.urlopen(req) as res:
                data = json.loads(res.read()).get("data", [])
                names = [d.get("attributes", {}).get("identifier") or d.get("attributes", {}).get("name")
                         or d.get("attributes", {}).get("certificateType") or d.get("id") for d in data]
                print(f"OK  {path}: {len(data)} {names[:20]}")
        except urllib.error.HTTPError as e:
            print(f"ERR {path}: {e.code} {e.read().decode()[:300]}")


def resend(_: str = "") -> None:
    """Re-sends the TestFlight invitation to every tester of the app who hasn't accepted yet."""
    app_id = call("GET", "/apps?filter[bundleId]=app.pushly")["data"][0]["id"]
    for t in call("GET", f"/betaTesters?filter[apps]={app_id}&limit=50")["data"]:
        if t["attributes"].get("state") in ("INVITED", "NOT_INVITED"):
            call("POST", "/betaTesterInvitations", {"data": {"type": "betaTesterInvitations", "relationships": {
                "betaTester": {"data": {"type": "betaTesters", "id": t["id"]}},
                "app": {"data": {"type": "apps", "id": app_id}}}}})
            print(f"invitation re-sent to {t['attributes'].get('email')}")


if __name__ == "__main__":
    {"create": create, "revoke": revoke, "diagnose": diagnose, "resend": resend}[sys.argv[1]](*sys.argv[2:])
