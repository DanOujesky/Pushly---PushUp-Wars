#!/usr/bin/env python3
"""Google Play store page through the Android Publisher API (workflow `android-store-setup`, D-085). One edit:
contact details, en-GB + en-US listing (title, short + full description from docs/store/listing.md), the 512 px icon
and the feature graphic (docs/store/graphics). Each part reports ok / failed; the edit is committed only when at
least one part went in. Needs PLAY_SERVICE_ACCOUNT_JSON with Play Console permission "Manage store presence".
Not possible through the API: Data safety, Ads declaration, content rating, target audience, app access — the
founder fills those in Play Console → App content.
"""
import json
import os
import pathlib
import sys

from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account

PKG = "app.pushly"
API = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PKG}"
UPLOAD = f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PKG}"
SITE = "https://danoujesky.github.io/Pushly---PushUp-Wars/"
EMAIL = "dany.oujesky@gmail.com"
TITLE = "Pushly – PushUp Wars"
SHORT = "The alarm that only stops after real push-ups. Battle friends, climb the ranks."
RESULTS: list[str] = []


def full_description() -> str:
    text = pathlib.Path("docs/store/listing.md").read_text()
    body = text.split("## Description (both stores)", 1)[1].split("\n## ", 1)[0].strip()
    body += ("\n\nPUSHLY PRO (optional subscription)\n• No ads, Pro alarm sounds, profile frames and clan emblems\n"
             "• Never pay-to-win\n\nPrivacy Policy: " + SITE + "privacy.html")
    return body[:4000]


def clean(text: str) -> str:
    return text.replace("{", "(").replace("}", ")")  # the secret is multi-line JSON; GitHub masks lines like "{"


def main() -> None:
    info = json.loads(os.environ["PLAY_SERVICE_ACCOUNT_JSON"])
    s = AuthorizedSession(service_account.Credentials.from_service_account_info(
        info, scopes=["https://www.googleapis.com/auth/androidpublisher"]))

    def part(name: str, method: str, url: str, **kw) -> dict | None:
        res = s.request(method, url, **kw)
        if res.status_code >= 300:
            try:
                msg = res.json().get("error", {}).get("message", res.text)
            except ValueError:
                msg = res.text
            hint = " (give the service account 'Manage store presence' in Play Console)" if res.status_code == 403 else ""
            RESULTS.append(f"{name}: FAILED {res.status_code} {clean(msg)[:400]}{hint}")
            print(RESULTS[-1], flush=True)
            return None
        RESULTS.append(f"{name}: ok")
        print(RESULTS[-1], flush=True)
        return res.json() if res.text else {}

    edit = part("open edit", "POST", f"{API}/edits", json={})
    if edit is None:
        print("::error title=Google Play store page::" + " | ".join(RESULTS))
        sys.exit(1)
    eid = edit["id"]
    details = s.get(f"{API}/edits/{eid}/details").json()
    default_lang = details.get("defaultLanguage") or "en-GB"
    part("contact details", "PUT", f"{API}/edits/{eid}/details",
         json={"defaultLanguage": default_lang, "contactEmail": EMAIL, "contactWebsite": SITE})
    langs = sorted({default_lang, "en-GB", "en-US"})
    for lang in langs:
        part(f"listing {lang}", "PUT", f"{API}/edits/{eid}/listings/{lang}",
             json={"language": lang, "title": TITLE, "shortDescription": SHORT, "fullDescription": full_description()})
        for kind, path in (("icon", "docs/store/graphics/play-icon-512.png"),
                           ("featureGraphic", "docs/store/graphics/play-feature-graphic.png")):
            data = pathlib.Path(path).read_bytes()
            s.delete(f"{API}/edits/{eid}/listings/{lang}/{kind}")
            part(f"{kind} {lang}", "POST", f"{UPLOAD}/edits/{eid}/listings/{lang}/{kind}?uploadType=media",
                 data=data, headers={"Content-Type": "image/png"})
    ok = [r for r in RESULTS if r.endswith(": ok") and not r.startswith("open edit")]
    if ok:
        res = s.post(f"{API}/edits/{eid}:commit")
        if res.status_code >= 300 and "changesNotSentForReview" in res.text:
            res = s.post(f"{API}/edits/{eid}:commit?changesNotSentForReview=true")
        RESULTS.append("commit: ok" if res.status_code < 300 else f"commit: FAILED {res.status_code} {clean(res.text)[:400]}")
    else:
        s.delete(f"{API}/edits/{eid}")
    print("::notice title=Google Play store page::" + " | ".join(RESULTS))


if __name__ == "__main__":
    main()
