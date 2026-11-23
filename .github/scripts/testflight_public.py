# Публічне тестування TestFlight через App Store Connect API:
# інформація для тестування, контакти для перевірки Apple, зовнішня група з публічним посиланням,
# найновіша збірка — в групу й на перевірку (Beta App Review). Повторний запуск безпечний.
# Персональні дані (контакти) — лише з секретів і в журнал не виводяться.
import os, sys, time, jwt, requests

API = "https://api.appstoreconnect.apple.com/v1"
PRIVACY = "https://bandface-store.bfapp.workers.dev/privacy"
GROUP = "Public"

DESCRIPTION = (
    "BandFace — watch faces for Xiaomi Smart Band 10 and 11: a store of ready-made faces, "
    "an editor to create your own, and installation on the band over Bluetooth.")
WHAT_TO_TEST = (
    "Store, watch-face previews, the editor (styles, colors, widgets), screenshots and installing faces on the band.")
REVIEW_NOTES = """BandFace installs watch faces on Xiaomi Smart Band 10/11 over Bluetooth Low Energy.

Without a band you can test:
- Store tab: browse watch faces, previews with styles and colors.
- Editor tab: open a sample face, change styles, colors, widgets, layers; take a screenshot / screenshot set.

Installing on a band requires a paired Xiaomi Smart Band and its authentication key (the user's own device key).
No account or sign-in is needed. The app collects no personal data."""


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                      os.environ["ASC_KEY_P8"], algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


H = {"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}


def call(method, path, ok=(), **kw):
    r = requests.request(method, API + path, headers=H, timeout=60, **kw)
    if r.status_code in ok:
        return None
    if r.status_code >= 400:
        errs = [e.get("detail") or e.get("title") for e in r.json().get("errors", [])] if r.content else []
        raise SystemExit(f"{method} {path.split('?')[0]} → {r.status_code}: {'; '.join(map(str, errs))}")
    return r.json() if r.content else {}


env = os.environ
contact = {k: env.get(v, "").strip() for k, v in
           [("first", "TF_CONTACT_FIRST_NAME"), ("last", "TF_CONTACT_LAST_NAME"), ("phone", "TF_CONTACT_PHONE"), ("email", "TF_CONTACT_EMAIL")]}
missing = [k for k, v in contact.items() if not v]
if missing:
    sys.exit("Не задано секрети контактів: " + ", ".join(missing))

app = call("GET", f"/apps?filter[bundleId]={env['BUNDLE_ID']}")["data"][0]
app_id, primary = app["id"], app["attributes"].get("primaryLocale") or "en-US"
print("Застосунок знайдено")

# 1. Інформація для тестування (основна мова й англійська)
locs = {l["attributes"]["locale"]: l["id"] for l in call("GET", f"/apps/{app_id}/betaAppLocalizations")["data"]}
attrs = {"description": DESCRIPTION, "feedbackEmail": contact["email"], "privacyPolicyUrl": PRIVACY}
for loc in dict.fromkeys([primary, "en-US"]):
    if loc in locs:
        call("PATCH", f"/betaAppLocalizations/{locs[loc]}", json={"data": {"type": "betaAppLocalizations", "id": locs[loc], "attributes": attrs}})
    else:
        call("POST", "/betaAppLocalizations", json={"data": {"type": "betaAppLocalizations", "attributes": {**attrs, "locale": loc},
             "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
print("Інформацію для тестування заповнено")

# 2. Контакти й примітки для перевірки Apple
det = call("GET", f"/apps/{app_id}/betaAppReviewDetail")["data"]
call("PATCH", f"/betaAppReviewDetails/{det['id']}", json={"data": {"type": "betaAppReviewDetails", "id": det["id"], "attributes": {
    "contactFirstName": contact["first"], "contactLastName": contact["last"], "contactPhone": contact["phone"],
    "contactEmail": contact["email"], "demoAccountRequired": False, "notes": REVIEW_NOTES}}})
print("Дані для перевірки заповнено")

# 3. Зовнішня група з публічним посиланням
groups = call("GET", f"/apps/{app_id}/betaGroups?limit=200")["data"]
group = next((g for g in groups if not g["attributes"].get("isInternalGroup") and g["attributes"]["name"] == GROUP), None)
if not group:
    group = call("POST", "/betaGroups", json={"data": {"type": "betaGroups",
        "attributes": {"name": GROUP, "publicLinkEnabled": True, "publicLinkLimitEnabled": False, "feedbackEnabled": True},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
    print(f"Створено зовнішню групу «{GROUP}»")
elif not group["attributes"].get("publicLinkEnabled"):
    call("PATCH", f"/betaGroups/{group['id']}", json={"data": {"type": "betaGroups", "id": group["id"],
         "attributes": {"publicLinkEnabled": True, "publicLinkLimitEnabled": False}}})
gid = group["id"]

# 4. Найновіша оброблена збірка (чекаємо обробки до ~40 хв)
for attempt in range(41):
    builds = call("GET", f"/builds?filter[app]={app_id}&sort=-uploadedDate&limit=1")["data"]
    if builds and builds[0]["attributes"].get("processingState") == "VALID":
        break
    if attempt == 40:
        sys.exit("Збірка ще обробляється — запустіть пізніше")
    time.sleep(60)
build = builds[0]
bid, num = build["id"], build["attributes"].get("version")
print(f"Збірка {num} готова")

# що тестувати — для кожної мови інформації
for loc in dict.fromkeys([primary, "en-US"]):
    call("POST", "/betaBuildLocalizations", ok=(409,), json={"data": {"type": "betaBuildLocalizations",
         "attributes": {"locale": loc, "whatsNew": WHAT_TO_TEST}, "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})

call("POST", f"/betaGroups/{gid}/relationships/builds", json={"data": [{"type": "builds", "id": bid}]})
print(f"Збірку {num} додано в групу «{GROUP}»")

# 5. На перевірку (якщо вже подано чи затверджено — пропуск)
state = call("GET", f"/builds/{bid}/buildBetaDetail")["data"]["attributes"].get("externalBuildState")
if state in ("READY_FOR_BETA_TESTING", "IN_BETA_TESTING", "WAITING_FOR_BETA_REVIEW", "IN_BETA_REVIEW", "BETA_APPROVED"):
    print(f"Стан збірки: {state} — повторно не подається")
else:
    call("POST", "/betaAppReviewSubmissions", ok=(409,), json={"data": {"type": "betaAppReviewSubmissions",
         "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
    print("Збірку подано на перевірку Apple (Beta App Review)")

link = call("GET", f"/betaGroups/{gid}")["data"]["attributes"].get("publicLink")
print(f"Публічне посилання: {link or 'з’явиться після затвердження збірки'}")
