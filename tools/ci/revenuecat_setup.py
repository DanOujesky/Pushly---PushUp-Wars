#!/usr/bin/env python3
"""RevenueCat for Pushly Pro through REST API v2 (workflow `revenuecat-setup`, D-085). Safe to run again.

Creates or updates: the App Store app (bundle app.pushly + the In-App Purchase key) and the Play Store app (package
app.pushly + the Play service account JSON), the products (App Store `pro_monthly`, `pro_yearly`; Play
`pro_monthly:monthly`, `pro_yearly:yearly`), the entitlement `pro` with all four, the offering `default` (current)
with packages `$rc_monthly` + `$rc_annual`, and the webhook to the Supabase function `revenuecat-webhook` — its
Authorization value is generated here and written straight into the Supabase secret REVENUECAT_WEBHOOK_AUTH (never
printed). Prints the public SDK keys (appl_…, goog_…) for the GitHub Variables REVENUECAT_IOS_KEY /
REVENUECAT_ANDROID_KEY.

Env: REVENUECAT_API_KEY (v2 secret key, project configuration read + write), PLAY_SERVICE_ACCOUNT_JSON,
ASC_IAP_KEY_ID + ASC_IAP_KEY_P8 (+ ASC_ISSUER_ID), SUPABASE_ACCESS_TOKEN + SUPABASE_PROJECT_REF.
"""
import json
import os
import secrets
import sys
import urllib.error
import urllib.request

RC = "https://api.revenuecat.com/v2"
BUNDLE = "app.pushly"
WEBHOOK_PATH = "/functions/v1/revenuecat-webhook"
PLANS = [("pro_monthly", "monthly", "$rc_monthly", "Monthly", "Pushly Pro Monthly"),
         ("pro_yearly", "yearly", "$rc_annual", "Annual", "Pushly Pro Yearly")]
RESULTS: list[str] = []


def clean(text: str) -> str:
    return text.replace("{", "(").replace("}", ")")  # multi-line JSON secrets get masked line by line in logs


def http(method: str, url: str, body=None, headers: dict | None = None, ok: tuple = ()) -> dict:
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json", **(headers or {})})
    try:
        with urllib.request.urlopen(req) as res:
            raw = res.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        if e.code in ok:
            return {"_status": e.code, "_body": text}
        sys.exit(f"::error title=RevenueCat::{method} {url.split('?')[0].replace(RC, '')} → {e.code} {clean(text)[:800]}")


def rc(method: str, path: str, body=None, ok: tuple = ()) -> dict:
    return http(method, RC + path, body, {"Authorization": f"Bearer {os.environ['REVENUECAT_API_KEY']}"}, ok)


def items(path: str) -> list[dict]:
    out, url = [], path + ("&" if "?" in path else "?") + "limit=100"
    while url:
        res = rc("GET", url)
        out += res.get("items", [])
        nxt = res.get("next_page")
        url = nxt.replace(RC, "") if nxt else None
    return out


def note(line: str) -> None:
    print(line, flush=True)
    RESULTS.append(line)


def project() -> str:
    projects = items("/projects")
    if not projects:
        sys.exit("::error title=RevenueCat::No project — create one called Pushly in the RevenueCat dashboard")
    p = next((p for p in projects if "pushly" in p.get("name", "").lower()), projects[0])
    note(f"project {p['name']}")
    return p["id"]


def apps(pid: str) -> tuple[str | None, str | None]:
    existing = items(f"/projects/{pid}/apps")
    ios = next((a for a in existing if a["type"] == "app_store" and (a.get("app_store") or {}).get("bundle_id") == BUNDLE), None)
    android = next((a for a in existing if a["type"] == "play_store" and
                    (a.get("play_store") or {}).get("package_name") == BUNDLE), None)

    store: dict = {"bundle_id": BUNDLE}
    if os.environ.get("ASC_IAP_KEY_P8") and os.environ.get("ASC_IAP_KEY_ID"):
        store |= {"subscription_private_key": os.environ["ASC_IAP_KEY_P8"].replace("\r", ""),
                  "subscription_key_id": os.environ["ASC_IAP_KEY_ID"],
                  "subscription_key_issuer": os.environ["ASC_ISSUER_ID"]}
    if ios:
        rc("POST", f"/projects/{pid}/apps/{ios['id']}", {"app_store": store})
        note("App Store app updated" + (" (+ In-App Purchase key)" if "subscription_key_id" in store else ""))
    else:
        ios = rc("POST", f"/projects/{pid}/apps", {"name": "Pushly (iOS)", "type": "app_store", "app_store": store})
        note("App Store app created" + (" (+ In-App Purchase key)" if "subscription_key_id" in store else ""))
    if "subscription_key_id" not in store:
        note("App Store: In-App Purchase key missing (secrets ASC_IAP_KEY_ID + ASC_IAP_KEY_P8)")

    play: dict = {"package_name": BUNDLE}
    if os.environ.get("PLAY_SERVICE_ACCOUNT_JSON"):
        play["play_service_account_credentials_json"] = os.environ["PLAY_SERVICE_ACCOUNT_JSON"]
    if android:
        rc("POST", f"/projects/{pid}/apps/{android['id']}", {"play_store": play})
        note("Play Store app updated (+ service account)")
    else:
        android = rc("POST", f"/projects/{pid}/apps", {"name": "Pushly (Android)", "type": "play_store", "play_store": play})
        note("Play Store app created (+ service account)")
    return ios["id"], android["id"]


def products(pid: str, ios: str, android: str) -> dict[str, list[str]]:
    existing = items(f"/projects/{pid}/products")
    by_key = {(p["app_id"], p["store_identifier"]): p["id"] for p in existing}
    out: dict[str, list[str]] = {}
    for product_id, base_plan, _, _, display in PLANS:
        ids = []
        for app, ident in ((ios, product_id), (android, f"{product_id}:{base_plan}")):
            pid_ = by_key.get((app, ident))
            if not pid_:
                pid_ = rc("POST", f"/projects/{pid}/products", {"store_identifier": ident, "app_id": app,
                          "type": "subscription", "display_name": display})["id"]
                note(f"product {ident} created")
            ids.append(pid_)
        out[product_id] = ids
    return out


def entitlement(pid: str, prods: dict[str, list[str]]) -> None:
    all_ents = items(f"/projects/{pid}/entitlements")
    ent = next((e for e in all_ents if e["lookup_key"] == "pro"), None)
    if not ent:
        others = ", ".join(f"{e['lookup_key']} ({e.get('display_name')})" for e in all_ents)
        if others:
            note(f"other entitlements already in the project (left alone; the apps use 'pro'): {others}")
        names = {e.get("display_name") for e in all_ents}
        name = "Pushly Pro" if "Pushly Pro" not in names else "Pushly Pro (pro)"
        ent = rc("POST", f"/projects/{pid}/entitlements", {"lookup_key": "pro", "display_name": name})
        note("entitlement pro created")
    attached = {p["id"] for p in items(f"/projects/{pid}/entitlements/{ent['id']}/products")}
    missing = [p for ids in prods.values() for p in ids if p not in attached]
    if missing:
        rc("POST", f"/projects/{pid}/entitlements/{ent['id']}/actions/attach_products", {"product_ids": missing})
        note(f"entitlement pro: {len(missing)} products attached")


def offering(pid: str, prods: dict[str, list[str]]) -> None:
    all_offs = items(f"/projects/{pid}/offerings")
    off = next((o for o in all_offs if o["lookup_key"] == "default"), None)
    if not off:
        names = {o.get("display_name") for o in all_offs}
        name = "Default" if "Default" not in names else "Default (Pushly Pro)"
        off = rc("POST", f"/projects/{pid}/offerings", {"lookup_key": "default", "display_name": name})
        note("offering default created")
    if not off.get("is_current"):
        rc("POST", f"/projects/{pid}/offerings/{off['id']}", {"is_current": True})
        note("offering default is current")
    pkgs = {p["lookup_key"]: p for p in items(f"/projects/{pid}/offerings/{off['id']}/packages")}
    for position, (product_id, _, key, name, _) in enumerate(PLANS, start=1):
        pkg = pkgs.get(key) or next((p for p in pkgs.values() if p.get("display_name") == name), None) or rc("POST", f"/projects/{pid}/offerings/{off['id']}/packages",
                                  {"lookup_key": key, "display_name": name, "position": position})
        have = {p["product"]["id"] if isinstance(p.get("product"), dict) else p.get("product_id")
                for p in items(f"/projects/{pid}/packages/{pkg['id']}/products")}
        missing = [p for p in prods[product_id] if p not in have]
        if missing:
            rc("POST", f"/projects/{pid}/packages/{pkg['id']}/actions/attach_products",
               {"products": [{"product_id": p, "eligibility_criteria": "all"} for p in missing]})
            note(f"package {key}: {len(missing)} products attached")


def webhook(pid: str) -> None:
    ref, token = os.environ.get("SUPABASE_PROJECT_REF"), os.environ.get("SUPABASE_ACCESS_TOKEN")
    if not ref or not token:
        note("webhook skipped (no Supabase access in this run)")
        return
    url = f"https://{ref}.supabase.co{WEBHOOK_PATH}"
    value = secrets.token_urlsafe(40)
    # Supabase first: the function must accept the new value before RevenueCat starts sending it
    http("POST", f"https://api.supabase.com/v1/projects/{ref}/secrets",
         [{"name": "REVENUECAT_WEBHOOK_AUTH", "value": value}], {"Authorization": f"Bearer {token}"})
    hooks = items(f"/projects/{pid}/integrations/webhooks")
    hook = next((h for h in hooks if h.get("url") == url), None)
    body = {"name": "Supabase (Pushly Pro)", "url": url, "authorization_header": value, "environment": None}
    if hook:
        rc("POST", f"/projects/{pid}/integrations/webhooks/{hook['id']}", body)
    else:
        rc("POST", f"/projects/{pid}/integrations/webhooks", body)
    note("webhook → Supabase revenuecat-webhook (auth value rotated, stored as Supabase secret)")


def public_keys(pid: str, ios: str, android: str) -> None:
    for app, var in ((ios, "REVENUECAT_IOS_KEY"), (android, "REVENUECAT_ANDROID_KEY")):
        keys = [k for k in items(f"/projects/{pid}/apps/{app}/public_api_keys") if k.get("environment") != "sandbox"]
        key = (keys or items(f"/projects/{pid}/apps/{app}/public_api_keys") or [{}])[0].get("key", "?")
        note(f"GitHub Variable {var} = {key}")


def main() -> None:
    if not os.environ.get("REVENUECAT_API_KEY"):
        sys.exit("::error title=RevenueCat::Secret REVENUECAT_API_KEY missing (RevenueCat → Project settings → API keys → "
                 "+ New → V2, Project configuration: read & write)")
    pid = project()
    ios, android = apps(pid)
    prods = products(pid, ios, android)
    entitlement(pid, prods)
    offering(pid, prods)
    webhook(pid)
    public_keys(pid, ios, android)
    print("::notice title=RevenueCat::" + " | ".join(RESULTS))


if __name__ == "__main__":
    main()
