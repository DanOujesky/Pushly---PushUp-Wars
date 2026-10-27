#!/usr/bin/env python3
"""App Store page + review setup through the App Store Connect API (workflow `ios-store-setup`, D-085). Everything
from docs/store (listing.md, compliance.md) that the API can set; each step is independent, safe to run again, and
reported as ok / skipped / failed (a failed step never blocks the others).

Sets: categories (Health & Fitness, Sports), name + subtitle + privacy URL per app-info localisation, content rights,
age rating answers (16+), a 1.0 version with description / keywords / promo text / support + marketing URLs,
App Review contact + notes, price Free, availability in all territories.
Not possible through the API (left for the founder): App Privacy answers, screenshots from a real device, the review
phone number, agreements / tax / bank.
Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8.
"""
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com"
BUNDLE = "app.pushly"
SITE = "https://danoujesky.github.io/Pushly---PushUp-Wars/"
PRIVACY = SITE + "privacy.html"
SUPPORT = SITE + "support.html"
TERMS = SITE + "terms.html"
EMAIL = "dany.oujesky@gmail.com"
NAME = "Pushly – PushUp Wars"
SUBTITLE = "Alarm that needs push-ups"
KEYWORDS = "pushup,push up,alarm,wake up,fitness,workout,challenge,battle,streak,habit,morning,counter,clan"
PROMO = "Wake up with push-ups, battle friends live and win the weekly Clan War."
REVIEW_NOTES = f"""Sign in: choose "Continue with email", enter any email address and the 6-digit code from that email (no password). Sign in with Apple works too.

How to test the alarm: Wake tab -> + -> set an alarm 1-2 minutes from now -> when it rings, open it, stand the phone upright about 2 m to your side and do 5 push-ups side-on to the camera. The camera counts only full reps.

Camera: frames are processed on the device with MediaPipe; no video is uploaded or recorded. Live battle video is relayed in real time (LiveKit) and never stored.
AlarmKit is the core feature (the wake-up challenge).

User-generated content: clan chat (profanity filter, report, block, leaders delete messages), usernames (filtered), live video battles (report, block).
Pushly Pro (optional subscription): no ads + cosmetics only, never pay-to-win. Profile -> Get Pushly Pro. Terms: {TERMS}
Account deletion: Profile -> Settings -> Account & data -> Delete account.
Contact: {EMAIL}"""
RESULTS: list[str] = []


def description() -> str:
    """docs/store/listing.md description + the Pro / Terms / Privacy lines Apple wants for subscriptions (3.1.2)."""
    text = pathlib.Path("docs/store/listing.md").read_text()
    body = text.split("## Description (both stores)", 1)[1].split("\n## ", 1)[0].strip()
    body += (f"\n\nPUSHLY PRO (optional subscription)\n• No ads, Pro alarm sounds, profile frames and clan emblems\n"
             f"• Never pay-to-win\n\nTerms of Use: {TERMS}\nPrivacy Policy: {PRIVACY}")
    return re.sub(r"\n{3,}", "\n\n", body)[:4000]


def token() -> str:
    now = int(time.time())
    key = os.environ["ASC_KEY_P8"].replace("\r", "")
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


class ApiError(Exception):
    pass


def call(method: str, path: str, body: dict | None = None) -> dict:
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
            try:
                errs = json.loads(text).get("errors", [])
                text = "; ".join(f"{x.get('title')}: {x.get('detail')}" for x in errs) or text
            except ValueError:
                pass
            raise ApiError(f"{method} {path.split('?')[0]} → {e.code} {text[:600]}")
    raise ApiError(f"{method} {path} kept failing")


def pages(path: str) -> list[dict]:
    out, url = [], path
    while url:
        res = call("GET", url)
        out += res.get("data", [])
        url = res.get("links", {}).get("next")
    return out


def rel(type_: str, id_: str) -> dict:
    return {"data": {"type": type_, "id": id_}}


def step(name: str):
    def wrap(fn):
        def run(*a):
            try:
                out = fn(*a)
                RESULTS.append(f"{name}: {out or 'ok'}")
            except ApiError as e:
                RESULTS.append(f"{name}: FAILED — {e}")
            print(RESULTS[-1], flush=True)
        return run
    return wrap


def editable_app_info(app: str) -> dict:
    infos = pages(f"/v1/apps/{app}/appInfos?limit=10")
    live = {"READY_FOR_DISTRIBUTION", "READY_FOR_SALE", "REPLACED_WITH_NEW_INFO"}
    return next((i for i in infos if i["attributes"].get("state") not in live and
                 i["attributes"].get("appStoreState") not in live), infos[0])


@step("categories")
def categories(app: str) -> str:
    info = editable_app_info(app)
    call("PATCH", f"/v1/appInfos/{info['id']}", {"data": {"type": "appInfos", "id": info["id"], "relationships": {
        "primaryCategory": rel("appCategories", "HEALTH_AND_FITNESS"),
        "secondaryCategory": rel("appCategories", "SPORTS")}}})
    return "Health & Fitness + Sports"


@step("name, subtitle, privacy URL")
def info_localizations(app: str) -> str:
    info = editable_app_info(app)
    done = []
    for loc in pages(f"/v1/appInfos/{info['id']}/appInfoLocalizations?limit=50"):
        call("PATCH", f"/v1/appInfoLocalizations/{loc['id']}", {"data": {"type": "appInfoLocalizations", "id": loc["id"],
             "attributes": {"name": NAME, "subtitle": SUBTITLE, "privacyPolicyUrl": PRIVACY}}})
        done.append(loc["attributes"]["locale"])
    return ", ".join(done)


@step("content rights")
def content_rights(app: str) -> str:
    call("PATCH", f"/v1/apps/{app}", {"data": {"type": "apps", "id": app,
         "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})
    return "no third-party content"


@step("age rating")
def age_rating(app: str) -> str:
    info = editable_app_info(app)
    decl = call("GET", f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    known = set(decl["attributes"].keys())
    wanted = {
        "alcoholTobaccoOrDrugUseOrReferences": "NONE", "contests": "NONE", "gamblingSimulated": "NONE",
        "horrorOrFearThemes": "NONE", "matureOrSuggestiveThemes": "NONE", "medicalOrTreatmentInformation": "NONE",
        "profanityOrCrudeHumor": "NONE", "sexualContentGraphicAndNudity": "NONE", "sexualContentOrNudity": "NONE",
        "violenceCartoonOrFantasy": "NONE", "violenceRealistic": "NONE",
        "violenceRealisticProlongedGraphicOrSadistic": "NONE", "gunsOrOtherWeapons": "NONE",
        "gambling": False, "unrestrictedWebAccess": False, "lootBox": False, "kidsAgeBand": None,
        "messagingAndChat": True, "userGeneratedContent": True, "advertising": True, "parentalControls": False,
        "ageAssurance": False, "healthOrWellnessTopics": True, "seventeenPlus": False,
        "ageRatingOverrideV2": "SIXTEEN_PLUS",
    }
    attrs = {k: v for k, v in wanted.items() if k in known}
    call("PATCH", f"/v1/ageRatingDeclarations/{decl['id']}", {"data": {"type": "ageRatingDeclarations",
         "id": decl["id"], "attributes": attrs}})
    missing = sorted(set(wanted) - known)
    return f"{len(attrs)} answers set" + (f" (API has no field for: {', '.join(missing)})" if missing else "")


def editable_version(app: str) -> dict:
    editable = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
    versions = pages(f"/v1/apps/{app}/appStoreVersions?filter[platform]=IOS&limit=20")
    found = next((v for v in versions if v["attributes"].get("appStoreState") in editable or
                  v["attributes"].get("appVersionState") in {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
                                                             "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}), None)
    if found:
        return found
    return call("POST", "/v1/appStoreVersions", {"data": {"type": "appStoreVersions",
                "attributes": {"platform": "IOS", "versionString": "1.0"},
                "relationships": {"app": rel("apps", app)}}})["data"]


@step("version text (description, keywords, URLs)")
def version_text(app: str) -> str:
    version = editable_version(app)
    attrs = {"description": description(), "keywords": KEYWORDS, "promotionalText": PROMO,
             "supportUrl": SUPPORT, "marketingUrl": SITE}
    locs = pages(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations?limit=50")
    for loc in locs:
        call("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {"data": {
             "type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": attrs}})
    return f"version {version['attributes'].get('versionString')} — {', '.join(l['attributes']['locale'] for l in locs)}"


@step("App Review contact + notes")
def review_details(app: str) -> str:
    version = editable_version(app)
    attrs = {"contactFirstName": "Dan", "contactLastName": "Oujesky", "contactEmail": EMAIL,
             "demoAccountRequired": False, "notes": REVIEW_NOTES}
    try:
        existing = call("GET", f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail").get("data")
    except ApiError:
        existing = None
    if existing:
        call("PATCH", f"/v1/appStoreReviewDetails/{existing['id']}", {"data": {"type": "appStoreReviewDetails",
             "id": existing["id"], "attributes": attrs}})
    else:
        call("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": attrs,
             "relationships": {"appStoreVersion": rel("appStoreVersions", version["id"])}}})
    return "contact Dan Oujesky, notes set (phone number: add in the web)"


@step("price Free")
def price_free(app: str) -> str:
    try:
        if call("GET", f"/v1/apps/{app}/appPriceSchedule").get("data"):
            current = call("GET", f"/v1/appPriceSchedules/{app}/manualPrices?include=appPricePoint&limit=5")
            if any(i["attributes"].get("customerPrice") in ("0", "0.0", "0.00")
                   for i in current.get("included", []) if i["type"] == "appPricePoints"):
                return "already Free"
    except ApiError:
        pass
    points = pages(f"/v1/apps/{app}/appPricePoints?filter[territory]=USA&limit=200")
    free = next(p for p in points if float(p["attributes"]["customerPrice"]) == 0)
    call("POST", "/v1/appPriceSchedules", {
        "data": {"type": "appPriceSchedules", "relationships": {
            "app": rel("apps", app), "baseTerritory": rel("territories", "USA"),
            "manualPrices": {"data": [{"type": "appPrices", "id": "${free}"}]}}},
        "included": [{"type": "appPrices", "id": "${free}", "attributes": {"startDate": None},
                      "relationships": {"appPricePoint": rel("appPricePoints", free["id"])}}]})
    return "Free"


@step("availability (all territories)")
def availability(app: str) -> str:
    try:
        if call("GET", f"/v1/apps/{app}/appAvailabilityV2").get("data"):
            return "already set"
    except ApiError:
        pass
    terrs = [t["id"] for t in pages("/v1/territories?limit=200")]
    call("POST", "/v2/appAvailabilities", {
        "data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
                 "relationships": {"app": rel("apps", app), "territoryAvailabilities": {
                     "data": [{"type": "territoryAvailabilities", "id": f"${{{t}}}"} for t in terrs]}}},
        "included": [{"type": "territoryAvailabilities", "id": f"${{{t}}}", "attributes": {"available": True},
                      "relationships": {"territory": rel("territories", t)}} for t in terrs]})
    return f"{len(terrs)} territories"


def main() -> None:
    app = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}")["data"][0]["id"]
    for fn in (categories, info_localizations, content_rights, age_rating, version_text, review_details,
               price_free, availability):
        fn(app)
    print("::notice title=App Store page::" + " | ".join(RESULTS))
    if any("FAILED" in r for r in RESULTS):
        print("::warning title=App Store page::some steps failed — see the lines above")


if __name__ == "__main__":
    main()
