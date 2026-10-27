#!/usr/bin/env python3
"""Pushly Pro in App Store Connect, through the API (workflow `ios-subscriptions`, D-083). Safe to run again: every
step checks what already exists and only adds what is missing.

    asc_subscriptions.py [screenshot.png]

Creates the subscription group "Pushly Pro" (+ en-US name), the auto-renewing subscriptions `pro_monthly` (1 month)
and `pro_yearly` (1 year) with en-US name + description, review notes, availability in every territory, prices from a
EUR base (Germany) equalised by Apple to all territories, a 1-week free trial on the yearly plan, and the review
screenshot (the paywall from the iOS CI screenshots) when one is given. Prints a summary as run annotations.

What the API cannot do (the founder does it in the web UI): the Paid Apps agreement, tax + bank, the In-App Purchase
key for RevenueCat, and submitting the subscriptions with the next app version.
Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8.
"""
import base64
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = "app.pushly"
GROUP = "Pushly Pro"
BASE_TERRITORY = "DEU"
PRIVACY = "https://danoujesky.github.io/Pushly---PushUp-Wars/privacy.html"
TERMS = "https://danoujesky.github.io/Pushly---PushUp-Wars/terms.html"
REVIEW_NOTE = (
    "Pushly Pro is an optional auto-renewable subscription: no ads, Pro alarm sounds, profile frames and extra clan "
    "emblems. It never affects battles, trophies or ranks. Open the app → Profile → Get Pushly Pro to see the paywall "
    f"(restore purchases at the bottom). Terms: {TERMS} Privacy: {PRIVACY}"
)
PLANS = [
    {"productId": "pro_monthly", "name": "Pro Monthly", "period": "ONE_MONTH", "price": "2.99", "trial": None,
     "display": "Pushly Pro (monthly)",
     "description": "No ads, Pro sounds, frames and emblems."},
    {"productId": "pro_yearly", "name": "Pro Yearly", "period": "ONE_YEAR", "price": "19.99", "trial": "ONE_WEEK",
     "display": "Pushly Pro (yearly)",
     "description": "A year of Pro: no ads, sounds, frames."},
]
SUMMARY: list[str] = []


def token() -> str:
    now = int(time.time())
    key = os.environ["ASC_KEY_P8"].replace("\r", "")
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method: str, path: str, body: dict | None = None, ok: tuple = ()) -> dict:
    url = path if path.startswith("http") else API + path
    for attempt in range(5):
        req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body is not None else None,
                                     headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req) as res:
                raw = res.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            text = e.read().decode()
            if e.code == 429 or e.code >= 500:
                time.sleep(5 * (attempt + 1))
                continue
            if e.code in ok:
                return {"_status": e.code, "_body": text}
            sys.exit(f"::error title=App Store Connect::{method} {path} failed: {e.code} {text[:1500]}")
    sys.exit(f"::error title=App Store Connect::{method} {path} kept failing (rate limit / server)")


def pages(path: str) -> list[dict]:
    out, included, url = [], [], path
    while url:
        res = call("GET", url)
        out += res.get("data", [])
        included += res.get("included", [])
        url = res.get("links", {}).get("next")
    pages.included = included  # type: ignore[attr-defined]
    return out


def territory_of(price_point: dict) -> str | None:
    """Territory of a price point: from the relationship, else from its id (base64 JSON with "t")."""
    terr = (price_point.get("relationships", {}).get("territory", {}).get("data") or {}).get("id")
    if terr:
        return terr
    raw = price_point["id"]
    try:
        return json.loads(base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4))).get("t")
    except (ValueError, json.JSONDecodeError):
        return None


def rel(type_: str, id_: str) -> dict:
    return {"data": {"type": type_, "id": id_}}


def note(line: str) -> None:
    print(line, flush=True)
    SUMMARY.append(line)


def app_id() -> str:
    return call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}")["data"][0]["id"]


def group(app: str) -> str:
    groups = pages(f"/v1/apps/{app}/subscriptionGroups?limit=50")
    found = next((g for g in groups if g["attributes"]["referenceName"] == GROUP), None)
    if found:
        gid = found["id"]
    else:
        gid = call("POST", "/v1/subscriptionGroups", {"data": {"type": "subscriptionGroups",
                    "attributes": {"referenceName": GROUP}, "relationships": {"app": rel("apps", app)}}})["data"]["id"]
        note(f"created subscription group {GROUP}")
    locs = pages(f"/v1/subscriptionGroups/{gid}/subscriptionGroupLocalizations?limit=50")
    if not any(l["attributes"]["locale"] == "en-US" for l in locs):
        call("POST", "/v1/subscriptionGroupLocalizations", {"data": {"type": "subscriptionGroupLocalizations",
             "attributes": {"locale": "en-US", "name": "Pushly Pro", "customAppName": "Pushly"},
             "relationships": {"subscriptionGroup": rel("subscriptionGroups", gid)}}})
        note("group name (en-US) added")
    return gid


def subscription(gid: str, plan: dict) -> str:
    subs = pages(f"/v1/subscriptionGroups/{gid}/subscriptions?limit=50")
    found = next((s for s in subs if s["attributes"]["productId"] == plan["productId"]), None)
    if found:
        sid = found["id"]
    else:
        sid = call("POST", "/v1/subscriptions", {"data": {"type": "subscriptions", "attributes": {
            "name": plan["name"], "productId": plan["productId"], "subscriptionPeriod": plan["period"],
            "familySharable": False, "reviewNote": REVIEW_NOTE, "groupLevel": 1 if plan["period"] == "ONE_YEAR" else 2},
            "relationships": {"group": rel("subscriptionGroups", gid)}}})["data"]["id"]
        note(f"created subscription {plan['productId']}")
    locs = pages(f"/v1/subscriptions/{sid}/subscriptionLocalizations?limit=50")
    if not any(l["attributes"]["locale"] == "en-US" for l in locs):
        call("POST", "/v1/subscriptionLocalizations", {"data": {"type": "subscriptionLocalizations",
             "attributes": {"locale": "en-US", "name": plan["display"], "description": plan["description"]},
             "relationships": {"subscription": rel("subscriptions", sid)}}})
        note(f"{plan['productId']}: name + description (en-US) added")
    return sid


def territories() -> list[str]:
    return [t["id"] for t in pages("/v1/territories?limit=200")]


def availability(sid: str, plan: dict, all_territories: list[str]) -> None:
    res = call("GET", f"/v1/subscriptions/{sid}/subscriptionAvailability", ok=(404,))
    if res.get("data"):
        return
    call("POST", "/v1/subscriptionAvailabilities", {"data": {"type": "subscriptionAvailabilities",
         "attributes": {"availableInNewTerritories": True},
         "relationships": {"subscription": rel("subscriptions", sid),
                           "availableTerritories": {"data": [{"type": "territories", "id": t} for t in all_territories]}}}})
    note(f"{plan['productId']}: available in {len(all_territories)} territories")


def prices(sid: str, plan: dict) -> None:
    existing = pages(f"/v1/subscriptions/{sid}/prices?limit=200&include=territory")
    have = {(p.get("relationships", {}).get("territory", {}).get("data") or {}).get("id") for p in existing}
    have.discard(None)
    points = pages(f"/v1/subscriptions/{sid}/pricePoints?filter[territory]={BASE_TERRITORY}&limit=200")
    base = next((p for p in points if p["attributes"]["customerPrice"] in (plan["price"], plan["price"] + "0")), None)
    if base is None:
        sys.exit(f"::error title=Prices::no {plan['price']} EUR price point in {BASE_TERRITORY} for {plan['productId']}")
    targets = [(BASE_TERRITORY, base["id"])]
    eq = pages(f"/v1/subscriptionPricePoints/{base['id']}/equalizations?limit=200&include=territory")
    for p in eq:
        terr = territory_of(p)
        if terr:
            targets.append((terr, p["id"]))
    added = 0
    for terr, pp in targets:
        if terr in have:
            continue
        call("POST", "/v1/subscriptionPrices", {"data": {"type": "subscriptionPrices",
             "attributes": {"preserveCurrentPrice": False},
             "relationships": {"subscription": rel("subscriptions", sid),
                               "subscriptionPricePoint": rel("subscriptionPricePoints", pp)}}}, ok=(409,))
        added += 1
    note(f"{plan['productId']}: {plan['price']} EUR base, prices in {len(targets)} territories ({added} new)")


def trial(sid: str, plan: dict, all_territories: list[str]) -> None:
    if not plan["trial"]:
        return
    existing = pages(f"/v1/subscriptions/{sid}/introductoryOffers?limit=200&include=territory")
    have = {(o.get("relationships", {}).get("territory", {}).get("data") or {}).get("id") for o in existing}
    added = 0
    for terr in all_territories:
        if terr in have:
            continue
        call("POST", "/v1/subscriptionIntroductoryOffers", {"data": {"type": "subscriptionIntroductoryOffers",
             "attributes": {"duration": plan["trial"], "offerMode": "FREE_TRIAL", "numberOfPeriods": 1},
             "relationships": {"subscription": rel("subscriptions", sid), "territory": rel("territories", terr)}}},
             ok=(409,))
        added += 1
    note(f"{plan['productId']}: 1-week free trial in {len(all_territories)} territories ({added} new)")


def review_screenshot(sid: str, plan: dict, path: str | None) -> None:
    if not path or not os.path.exists(path):
        note(f"{plan['productId']}: no review screenshot given (add it before submitting)")
        return
    res = call("GET", f"/v1/subscriptions/{sid}/appStoreReviewScreenshot", ok=(404,))
    if res.get("data"):
        return
    data = open(path, "rb").read()
    shot = call("POST", "/v1/subscriptionAppStoreReviewScreenshots", {"data": {
        "type": "subscriptionAppStoreReviewScreenshots",
        "attributes": {"fileName": os.path.basename(path), "fileSize": len(data)},
        "relationships": {"subscription": rel("subscriptions", sid)}}})["data"]
    for op in shot["attributes"]["uploadOperations"]:
        chunk = data[op["offset"]: op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], method=op["method"], data=chunk,
                                     headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])})
        urllib.request.urlopen(req).read()
    call("PATCH", f"/v1/subscriptionAppStoreReviewScreenshots/{shot['id']}", {"data": {
        "type": "subscriptionAppStoreReviewScreenshots", "id": shot["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    note(f"{plan['productId']}: review screenshot uploaded")


def states(gid: str) -> None:
    for s in pages(f"/v1/subscriptionGroups/{gid}/subscriptions?limit=50"):
        a = s["attributes"]
        res = call("GET", f"/v1/subscriptions/{s['id']}/prices?filter[territory]={BASE_TERRITORY}"
                          "&include=subscriptionPricePoint&limit=5")
        price = next((i["attributes"].get("customerPrice") for i in res.get("included", [])
                      if i["type"] == "subscriptionPricePoints"), "?")
        shot = call("GET", f"/v1/subscriptions/{s['id']}/appStoreReviewScreenshot", ok=(404,))
        shot_state = ((shot.get("data") or {}).get("attributes", {}).get("assetDeliveryState") or {}).get("state", "none")
        note(f"{a['productId']}: state {a.get('state')}, {BASE_TERRITORY} price {price} EUR, review screenshot {shot_state}")


def privacy_url(app: str) -> None:
    """Privacy Policy URL on the app's info (en-US), needed before subscriptions can be submitted."""
    infos = pages(f"/v1/apps/{app}/appInfos?limit=10")
    for info in infos:
        for loc in pages(f"/v1/appInfos/{info['id']}/appInfoLocalizations?limit=50"):
            if loc["attributes"].get("privacyPolicyUrl"):
                continue
            call("PATCH", f"/v1/appInfoLocalizations/{loc['id']}", {"data": {"type": "appInfoLocalizations",
                 "id": loc["id"], "attributes": {"privacyPolicyUrl": PRIVACY}}}, ok=(409,))
            note(f"privacy policy URL set ({loc['attributes'].get('locale')})")


def main() -> None:
    shot = sys.argv[1] if len(sys.argv) > 1 else None
    app = app_id()
    privacy_url(app)
    gid = group(app)
    all_territories = territories()
    for plan in PLANS:
        sid = subscription(gid, plan)
        availability(sid, plan, all_territories)
        prices(sid, plan)
        trial(sid, plan, all_territories)
        review_screenshot(sid, plan, shot)
    states(gid)
    print("::notice title=Pushly Pro in App Store Connect::" + " | ".join(SUMMARY).replace("\n", " "))


if __name__ == "__main__":
    main()
