#!/usr/bin/env python3
"""Pushly Pro in Google Play, through the Android Publisher API (workflow `android-subscriptions`, D-084). Same
plans as the App Store (D-083), safe to run again — only adds what is missing.

Creates the subscriptions `pro_monthly` (base plan `monthly`, P1M, 2.99 EUR) and `pro_yearly` (base plan `yearly`,
P1Y, 19.99 EUR) with an en-US listing, prices in every Play region converted by Google from the EUR price, activates
the base plans, and adds an active 7-day free-trial offer `trial-7d` (new customers) to the yearly plan.

Needs secret PLAY_SERVICE_ACCOUNT_JSON: a Google Cloud service account invited in Play Console with "Manage orders and
subscriptions" + "View financial data" (the same account RevenueCat uses). Play only allows subscriptions once the
app has an uploaded build and the developer account has a payments profile.
"""
import json
import os
import sys

from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account

PKG = "app.pushly"
API = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PKG}"
REGIONS_VERSION = "2022/02"
PLANS = [
    {"productId": "pro_monthly", "basePlanId": "monthly", "period": "P1M", "eur": (2, 990_000_000), "trial": None,
     "title": "Pushly Pro (monthly)"},
    {"productId": "pro_yearly", "basePlanId": "yearly", "period": "P1Y", "eur": (19, 990_000_000), "trial": "P1W",
     "title": "Pushly Pro (yearly)"},
]
BENEFITS = ["No ads", "Pro alarm sounds", "Profile frames and clan emblems", "2 streak freezes a month"]
DESCRIPTION = "No ads, Pro alarm sounds, profile frames and clan emblems. Never pay-to-win."
SUMMARY: list[str] = []


def session() -> AuthorizedSession:
    info = json.loads(os.environ["PLAY_SERVICE_ACCOUNT_JSON"])
    creds = service_account.Credentials.from_service_account_info(
        info, scopes=["https://www.googleapis.com/auth/androidpublisher"])
    return AuthorizedSession(creds)


def call(s: AuthorizedSession, method: str, url: str, body: dict | None = None, ok: tuple = ()) -> dict:
    res = s.request(method, url, json=body)
    if res.status_code in ok:
        return {"_status": res.status_code, "_body": res.text}
    if res.status_code >= 300:
        hint = ""
        if res.status_code in (401, 403):
            hint = (" — check that the service account is invited in Play Console (Users and permissions) with "
                    "'Manage orders and subscriptions' and that the Google Play Android Developer API is enabled")
        sys.exit(f"::error title=Google Play::{method} {url.replace(API, '')} failed: {res.status_code} "
                 f"{res.text[:1500]}{hint}")
    return res.json() if res.text else {}


def note(line: str) -> None:
    print(line, flush=True)
    SUMMARY.append(line)


def money(currency: str, units: int, nanos: int) -> dict:
    return {"currencyCode": currency, "units": str(units), "nanos": nanos}


def converted(s: AuthorizedSession, plan: dict) -> tuple[list[dict], dict]:
    """Prices for every region Google converts the EUR price to + the 'other regions' prices."""
    units, nanos = plan["eur"]
    res = call(s, "POST", f"{API}/pricing:convertRegionPrices", {"price": money("EUR", units, nanos)})
    regional = [{"regionCode": code, "newSubscriberAvailability": True, "price": v["price"]}
                for code, v in sorted(res.get("convertedRegionPrices", {}).items())]
    other = res.get("convertedOtherRegionsPrice", {})
    return regional, {"usdPrice": other.get("usdPrice"), "eurPrice": other.get("eurPrice") or money("EUR", units, nanos),
                      "newSubscriberAvailability": True}


def subscription(s: AuthorizedSession, plan: dict) -> dict:
    existing = call(s, "GET", f"{API}/subscriptions/{plan['productId']}", ok=(404,))
    if "_status" not in existing:
        if not any(b["basePlanId"] == plan["basePlanId"] for b in existing.get("basePlans", [])):
            note(f"{plan['productId']}: exists without base plan '{plan['basePlanId']}' — add it in Play Console or "
                 "rename the base plan in tools/ci/play_subscriptions.py")
        return existing
    regional, other = converted(s, plan)
    body = {
        "packageName": PKG,
        "productId": plan["productId"],
        "listings": [{"languageCode": "en-US", "title": plan["title"], "benefits": BENEFITS, "description": DESCRIPTION}],
        "basePlans": [{
            "basePlanId": plan["basePlanId"],
            "autoRenewingBasePlanType": {
                "billingPeriodDuration": plan["period"],
                "gracePeriodDuration": "P3D",
                "resubscribeState": "RESUBSCRIBE_STATE_ACTIVE",
                "prorationMode": "SUBSCRIPTION_PRORATION_MODE_CHARGE_ON_NEXT_BILLING_DATE",
                "legacyCompatible": True,
            },
            "regionalConfigs": regional,
            "otherRegionsConfig": other,
        }],
    }
    created = call(s, "POST", f"{API}/subscriptions?productId={plan['productId']}"
                              f"&regionsVersion.version={REGIONS_VERSION}", body)
    note(f"created {plan['productId']} with base plan {plan['basePlanId']} ({len(regional)} regions)")
    return created


def activate(s: AuthorizedSession, plan: dict, sub: dict) -> None:
    base = next((b for b in sub.get("basePlans", []) if b["basePlanId"] == plan["basePlanId"]), None)
    if base is None or base.get("state") == "ACTIVE":
        return
    call(s, "POST", f"{API}/subscriptions/{plan['productId']}/basePlans/{plan['basePlanId']}:activate",
         {"packageName": PKG, "productId": plan["productId"], "basePlanId": plan["basePlanId"]})
    note(f"{plan['productId']}: base plan {plan['basePlanId']} activated")


def trial(s: AuthorizedSession, plan: dict, sub: dict) -> None:
    if not plan["trial"]:
        return
    offer_id = "trial-7d"
    path = f"{API}/subscriptions/{plan['productId']}/basePlans/{plan['basePlanId']}/offers"
    existing = call(s, "GET", f"{path}/{offer_id}", ok=(404,))
    if "_status" in existing:
        base = next((b for b in sub.get("basePlans", []) if b["basePlanId"] == plan["basePlanId"]), {})
        regions = [r["regionCode"] for r in base.get("regionalConfigs", [])]
        body = {
            "packageName": PKG, "productId": plan["productId"], "basePlanId": plan["basePlanId"], "offerId": offer_id,
            "phases": [{"recurrenceCount": 1, "duration": plan["trial"],
                        "regionalConfigs": [{"regionCode": r, "free": {}} for r in regions],
                        "otherRegionsConfig": {"free": {}}}],
            "targeting": {"acquisitionRule": {"scope": {"anySubscriptionInApp": {}}}},
            "regionalConfigs": [{"regionCode": r, "newSubscriberAvailability": True} for r in regions],
            "otherRegionsConfig": {"otherRegionsNewSubscriberAvailability": True},
            "offerTags": [{"tag": "free-trial"}],
        }
        existing = call(s, "POST", f"{path}?offerId={offer_id}&regionsVersion.version={REGIONS_VERSION}", body)
        note(f"{plan['productId']}: 7-day free trial offer created")
    if existing.get("state") != "ACTIVE":
        call(s, "POST", f"{path}/{offer_id}:activate", {"packageName": PKG, "productId": plan["productId"],
                                                         "basePlanId": plan["basePlanId"], "offerId": offer_id})
        note(f"{plan['productId']}: free trial activated")


def states(s: AuthorizedSession) -> None:
    for plan in PLANS:
        sub = call(s, "GET", f"{API}/subscriptions/{plan['productId']}", ok=(404,))
        for b in sub.get("basePlans", []):
            eur = next((r["price"] for r in b.get("regionalConfigs", []) if r["regionCode"] == "DE"), None)
            price = f"{eur['units']}.{str(eur.get('nanos', 0)).zfill(9)[:2]} EUR" if eur else "?"
            note(f"{plan['productId']}/{b['basePlanId']}: {b.get('state')}, DE price {price}")


def main() -> None:
    if not os.environ.get("PLAY_SERVICE_ACCOUNT_JSON"):
        sys.exit("::error title=Google Play::Secret PLAY_SERVICE_ACCOUNT_JSON is missing (docs/RELEASING.md)")
    s = session()
    for plan in PLANS:
        sub = subscription(s, plan)
        activate(s, plan, sub)
        sub = call(s, "GET", f"{API}/subscriptions/{plan['productId']}")
        trial(s, plan, sub)
    states(s)
    print("::notice title=Pushly Pro in Google Play::" + " | ".join(SUMMARY))


if __name__ == "__main__":
    main()
