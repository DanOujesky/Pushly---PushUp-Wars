#!/usr/bin/env python3
"""App Store signing for one CI run, entirely through the App Store Connect API (ios-testflight.yml, D-042).

Xcode's own `-allowProvisioningUpdates` login fails on hosted runners ("Authentication failed: bearer token") even
though the same key works against the API, so CI signs manually with throw-away material:

    asc_sign.py setup <outdir>     bundle IDs + capabilities, a temporary Apple Distribution certificate (key made on
                                   the runner) and App Store profiles for the app and the widget extension.
                                   Writes dist.p12, password, profiles/*.mobileprovision and signing.json.
    asc_sign.py cleanup <outdir>   deletes the profiles and revokes the certificate (run with `if: always()`).

Nothing is stored anywhere. App Groups: the API cannot assign an app group to an App ID; if `group.app.pushly` is not
assigned in the developer portal, signing.json reports it and the workflow strips that entitlement (the app then
falls back to its own container; see docs/RELEASING.md for the one-time portal step).
Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8.
"""
import base64
import json
import os
import plistlib
import secrets
import sys
import time
import urllib.parse
import urllib.request

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

API = "https://api.appstoreconnect.apple.com/v1"
APP_GROUP = "group.app.pushly"
# bundle id → (name, capabilities to enable)
TARGETS = {
    "app.pushly": ("Pushly", ["APP_GROUPS", "APPLE_ID_AUTH", "PUSH_NOTIFICATIONS"]),
    "app.pushly.widgets": ("Pushly Widgets", ["APP_GROUPS"]),
}


def token() -> str:
    now = int(time.time())
    key = os.environ["ASC_KEY_P8"].replace("\r", "")
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method: str, path: str, body: dict | None = None, ok_codes: tuple = ()) -> dict:
    req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as res:
            raw = res.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        if e.code in ok_codes:
            return {"_status": e.code, "_body": text}
        sys.exit(f"App Store Connect API {method} {path} failed: {e.code} {text[:800]}")


def bundle_id(identifier: str, name: str) -> str:
    q = urllib.parse.quote(identifier)
    found = [d for d in call("GET", f"/bundleIds?filter[identifier]={q}&limit=5")["data"]
             if d["attributes"]["identifier"] == identifier]
    if found:
        return found[0]["id"]
    res = call("POST", "/bundleIds", {"data": {"type": "bundleIds", "attributes": {
        "identifier": identifier, "name": name, "platform": "IOS"}}})
    print(f"registered bundle id {identifier}")
    return res["data"]["id"]


def enable_capabilities(bid: str, wanted: list[str]) -> None:
    have = {c["attributes"]["capabilityType"]
            for c in call("GET", f"/bundleIds/{bid}/bundleIdCapabilities")["data"]}
    for cap in wanted:
        if cap in have:
            continue
        attrs: dict = {"capabilityType": cap}
        if cap == "APPLE_ID_AUTH":
            attrs["settings"] = [{"key": "APPLE_ID_AUTH_APP_CONSENT",
                                  "options": [{"key": "PRIMARY_APP_CONSENT"}]}]
        call("POST", "/bundleIdCapabilities", {"data": {"type": "bundleIdCapabilities", "attributes": attrs,
                                                        "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bid}}}}})
        print(f"enabled {cap} on {bid}")


def certificate(outdir: str) -> str:
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (x509.CertificateSigningRequestBuilder()
           .subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Pushly CI"),
                                    x509.NameAttribute(NameOID.COUNTRY_NAME, "CZ")]))
           .sign(key, hashes.SHA256()))
    res = call("POST", "/certificates", {"data": {"type": "certificates", "attributes": {
        "csrContent": csr.public_bytes(serialization.Encoding.PEM).decode(), "certificateType": "DISTRIBUTION"}}})
    cert = x509.load_der_x509_certificate(base64.b64decode(res["data"]["attributes"]["certificateContent"]))
    password = secrets.token_urlsafe(24)
    enc = (serialization.PrivateFormat.PKCS12.encryption_builder().kdf_rounds(50000)
           .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC).hmac_hash(hashes.SHA1())
           .build(password.encode()))
    with open(os.path.join(outdir, "dist.p12"), "wb") as f:
        f.write(pkcs12.serialize_key_and_certificates(b"Pushly CI", key, cert, None, enc))
    with open(os.path.join(outdir, "password"), "w") as f:
        f.write(password)
    print(f"created distribution certificate {res['data']['id']}")
    return res["data"]["id"]


def profile(outdir: str, bid: str, identifier: str, cert_id: str) -> dict:
    name = f"Pushly CI {identifier} {int(time.time())}"
    res = call("POST", "/profiles", {"data": {"type": "profiles", "attributes": {
        "name": name, "profileType": "IOS_APP_STORE"}, "relationships": {
        "bundleId": {"data": {"type": "bundleIds", "id": bid}},
        "certificates": {"data": [{"type": "certificates", "id": cert_id}]}}}})
    content = base64.b64decode(res["data"]["attributes"]["profileContent"])
    os.makedirs(os.path.join(outdir, "profiles"), exist_ok=True)
    path = os.path.join(outdir, "profiles", f"{res['data']['attributes']['uuid']}.mobileprovision")
    with open(path, "wb") as f:
        f.write(content)
    # The profile is CMS-signed; the embedded plist sits between <?xml and </plist>.
    start, end = content.find(b"<?xml"), content.find(b"</plist>") + len(b"</plist>")
    ents = plistlib.loads(content[start:end]).get("Entitlements", {})
    groups = ents.get("com.apple.security.application-groups", [])
    return {"id": res["data"]["id"], "name": name, "uuid": res["data"]["attributes"]["uuid"], "path": path,
            "appGroup": APP_GROUP in groups}


def setup(outdir: str) -> None:
    os.makedirs(outdir, exist_ok=True)
    state: dict = {"profiles": {}}
    ids = {}
    for identifier, (name, caps) in TARGETS.items():
        ids[identifier] = bundle_id(identifier, name)
        enable_capabilities(ids[identifier], caps)
    state["certificateId"] = certificate(outdir)
    with open(os.path.join(outdir, "signing.json"), "w") as f:   # saved early so cleanup can revoke on failure
        json.dump(state, f)
    for identifier in TARGETS:
        state["profiles"][identifier] = profile(outdir, ids[identifier], identifier, state["certificateId"])
        with open(os.path.join(outdir, "signing.json"), "w") as f:
            json.dump(state, f, indent=2)
    state["appGroup"] = all(p["appGroup"] for p in state["profiles"].values())
    with open(os.path.join(outdir, "signing.json"), "w") as f:
        json.dump(state, f, indent=2)
    print(json.dumps({k: v for k, v in state.items() if k != "profiles"}),
          {k: v["name"] for k, v in state["profiles"].items()})


def cleanup(outdir: str) -> None:
    path = os.path.join(outdir, "signing.json")
    if not os.path.exists(path):
        return
    state = json.load(open(path))
    for p in state.get("profiles", {}).values():
        call("DELETE", f"/profiles/{p['id']}", ok_codes=(404, 409))
    if state.get("certificateId"):
        call("DELETE", f"/certificates/{state['certificateId']}", ok_codes=(404, 409))
    print("signing material removed")


def value(outdir: str, key: str) -> None:
    """Prints one value for shell use: appGroup | profile:<bundle id>."""
    state = json.load(open(os.path.join(outdir, "signing.json")))
    if key == "appGroup":
        print("true" if state.get("appGroup") else "false")
    elif key.startswith("profile:"):
        print(state["profiles"][key.split(":", 1)[1]]["name"])


def builds() -> None:
    """Latest TestFlight builds of app.pushly with Apple's processing and beta state (as GitHub notices)."""
    apps = call("GET", "/apps?filter[bundleId]=app.pushly")["data"]
    if not apps:
        sys.exit("app.pushly not found in App Store Connect")
    app_id = apps[0]["id"]
    res = call("GET", f"/builds?filter[app]={app_id}&sort=-uploadedDate&limit=6&include=buildBetaDetail,preReleaseVersion")
    included = {(i["type"], i["id"]): i["attributes"] for i in res.get("included", [])}
    for b in res["data"]:
        a = b["attributes"]
        rel = b.get("relationships", {})
        beta = included.get(("buildBetaDetails", (rel.get("buildBetaDetail", {}).get("data") or {}).get("id")), {})
        ver = included.get(("preReleaseVersions", (rel.get("preReleaseVersion", {}).get("data") or {}).get("id")), {})
        line = (f"build {a.get('version')} (v{ver.get('version', '?')}) uploaded {a.get('uploadedDate')} — "
                f"processing {a.get('processingState')}, internal {beta.get('internalBuildState')}, "
                f"external {beta.get('externalBuildState')}, expired {a.get('expired')}, "
                f"encryption {a.get('usesNonExemptEncryption')}")
        print(f"::notice title=TestFlight build {a.get('version')}::{line}")


def wait_build(version: str, minutes: int = 45) -> None:
    """Waits until Apple has processed build `version`; fails when it never shows up or processing fails."""
    app_id = call("GET", "/apps?filter[bundleId]=app.pushly")["data"][0]["id"]
    deadline = time.time() + minutes * 60
    state = None
    while time.time() < deadline:
        data = call("GET", f"/builds?filter[app]={app_id}&filter[version]={version}&include=buildBetaDetail")
        if data["data"]:
            a = data["data"][0]["attributes"]
            beta = next((i["attributes"] for i in data.get("included", []) if i["type"] == "buildBetaDetails"), {})
            state = a.get("processingState")
            print(f"build {version}: processing {state}, internal {beta.get('internalBuildState')}", flush=True)
            if state == "VALID":
                print(f"::notice title=TestFlight::Build {version} processed by Apple — "
                      f"internal testing: {beta.get('internalBuildState')}")
                return
            if state in ("FAILED", "INVALID"):
                sys.exit(f"::error title=TestFlight::Apple rejected build {version} ({state}) — check the App Store Connect e-mail")
        else:
            print(f"build {version}: not visible in App Store Connect yet", flush=True)
        time.sleep(60)
    sys.exit(f"::error title=TestFlight::Build {version} did not finish processing in {minutes} min (last state: {state}). "
             "If it never appeared, Apple rejected the upload — see the App Store Connect e-mail.")


def crashes(limit: int = 5) -> None:
    """Prints the newest TestFlight crash reports testers shared (Share on the crash dialog), symbolicated by Apple."""
    app_id = call("GET", "/apps?filter[bundleId]=app.pushly")["data"][0]["id"]
    res = call("GET", f"/apps/{app_id}/betaFeedbackCrashSubmissions?limit={limit}&sort=-createdDate", ok_codes=(403, 404))
    if "_status" in res:
        print(f"crash submissions not available: {res['_status']} {res['_body'][:300]}")
        return
    if not res.get("data"):
        print("no shared TestFlight crash reports")
        return
    for c in res["data"]:
        a = c["attributes"]
        print(f"=== crash {c['id']} at {a.get('createdDate')} build {a.get('buildBundleId', '')} "
              f"device {a.get('deviceModel')} iOS {a.get('osVersion')} comment: {a.get('comment')}")
        log = call("GET", f"/betaFeedbackCrashSubmissions/{c['id']}/crashLog", ok_codes=(403, 404))
        text = (log.get("data") or {}).get("attributes", {}).get("logText") if "_status" not in log else None
        if not text:
            print(f"::notice title=crash {c['id']}::no log ({log.get('_status')})")
            continue
        lines = text.splitlines()
        keep = [ln for ln in lines[:80] if ln.split(":")[0] in ("Exception Type", "Exception Codes", "Termination Reason",
                                                                  "Triggered by Thread", "Crashed Thread", "Version",
                                                                  "OS Version", "Date/Time")]
        start = next((i for i, ln in enumerate(lines) if "Crashed:" in ln), None)
        if start is not None:
            keep += lines[start:start + 45]
        # one annotation per crash (newlines as %0A); the full log stays in the job log
        msg = "%0A".join(ln.replace("%", "%25").replace("::", ": :")[:200] for ln in keep)[:60000]
        print(f"::warning title=crash {a.get('createdDate')}::{msg}")
        print(text[:12000])


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "wait":
        wait_build(sys.argv[2])
        sys.exit(0)
    if cmd == "value":
        value(sys.argv[2], sys.argv[3])
    elif cmd == "builds":
        builds()
    elif cmd == "crashes":
        crashes()
    else:
        {"setup": setup, "cleanup": cleanup}[cmd](sys.argv[2])
