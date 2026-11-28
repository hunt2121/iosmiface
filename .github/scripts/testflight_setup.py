# Налаштування TestFlight через App Store Connect API: внутрішня група з доступом до всіх збірок
# і всі користувачі команди в ній. Адреси не друкуються (журнали публічного репозиторію видно всім).
import os, sys, time, jwt, requests

API = "https://api.appstoreconnect.apple.com/v1"


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                      os.environ["ASC_KEY_P8"], algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


H = {"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}


def call(method, path, **kw):
    r = requests.request(method, API + path, headers=H, timeout=60, **kw)
    if r.status_code >= 400:
        # тексти помилок Apple — без персональних даних
        errs = [e.get("detail") or e.get("title") for e in r.json().get("errors", [])] if r.content else []
        raise SystemExit(f"{method} {path.split('?')[0]} → {r.status_code}: {'; '.join(map(str, errs))}")
    return r.json() if r.content else {}


if os.environ.get("REGISTER_ONLY"):
    bid = os.environ["BUNDLE_ID"]
    if call("GET", f"/bundleIds?filter[identifier]={bid}")["data"]:
        print(f"Bundle ID {bid} уже зареєстровано")
    else:
        call("POST", "/bundleIds", json={"data": {"type": "bundleIds",
             "attributes": {"identifier": bid, "name": bid.replace(".", " "), "platform": "IOS"}}})
        print(f"Зареєстровано Bundle ID {bid}")
    sys.exit(0)

app = call("GET", f"/apps?filter[bundleId]={os.environ['BUNDLE_ID']}")["data"]
if not app:
    sys.exit("Застосунок з цим Bundle ID не знайдено в App Store Connect")
app_id = app[0]["id"]
print("Застосунок знайдено")

name = os.environ["GROUP_NAME"]
groups = call("GET", f"/apps/{app_id}/betaGroups?limit=200")["data"]
group = next((g for g in groups if g["attributes"].get("isInternalGroup") and g["attributes"]["name"] == name), None)
if group:
    print(f"Внутрішня група «{name}» вже є")
else:
    group = call("POST", "/betaGroups", json={"data": {
        "type": "betaGroups",
        "attributes": {"name": name, "isInternalGroup": True, "hasAccessToAllBuilds": True},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})["data"]
    print(f"Створено внутрішню групу «{name}» (доступ до всіх збірок)")
gid = group["id"]

existing = {t["attributes"].get("email", "").lower() for t in call("GET", f"/betaGroups/{gid}/betaTesters?limit=200")["data"]}
users = call("GET", "/users?limit=200")["data"]
added = 0
for u in users:
    a = u["attributes"]
    email = (a.get("username") or a.get("email") or "").lower()
    if not email or email in existing:
        continue
    call("POST", "/betaTesters", json={"data": {
        "type": "betaTesters",
        "attributes": {"email": email, "firstName": a.get("firstName") or "", "lastName": a.get("lastName") or ""},
        "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": gid}]}}}})
    added += 1
print(f"Користувачів команди: {len(users)}; додано в групу: {added}; уже були: {len(existing)}")

# листи-запрошення TestFlight всім тестерам групи (на пошту акаунта); адреси не друкуються
if os.environ.get("SEND_INVITES"):
    sent = 0
    for t in call("GET", f"/betaGroups/{gid}/betaTesters?limit=200")["data"]:
        r = requests.post(API + "/betaTesterInvitations", headers=H, timeout=60, json={"data": {
            "type": "betaTesterInvitations",
            "relationships": {"betaTester": {"data": {"type": "betaTesters", "id": t["id"]}},
                              "app": {"data": {"type": "apps", "id": app_id}}}}})
        if r.status_code < 300:
            sent += 1
        else:
            errs = [e.get("detail") or e.get("title") for e in r.json().get("errors", [])] if r.content else []
            print(f"Запрошення не надіслано ({r.status_code}): {'; '.join(map(str, errs))}")
    print(f"Надіслано запрошень: {sent}")
