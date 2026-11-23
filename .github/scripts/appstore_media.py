# Сторінка App Store (чернетка версії): номер версії як у збірці, найновіша збірка (з неї — іконка),
# скріншоти з appstore/screenshots/<мова>/*.png (6,7″/6,9″, 1290×2796). На перевірку НЕ подає.
import os, sys, time, glob, hashlib, jwt, requests

API = "https://api.appstoreconnect.apple.com/v1"
DISPLAY = "APP_IPHONE_67"   # 6,7″ / 6,9″ — обов'язковий набір для iPhone


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                      os.environ["ASC_KEY_P8"], algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


H = {"Authorization": f"Bearer {token()}", "Content-Type": "application/json"}


def call(method, path, **kw):
    r = requests.request(method, API + path, headers=H, timeout=120, **kw)
    if r.status_code >= 400:
        errs = [e.get("detail") or e.get("title") for e in r.json().get("errors", [])] if r.content else []
        raise SystemExit(f"{method} {path.split('?')[0]} → {r.status_code}: {'; '.join(map(str, errs))}")
    return r.json() if r.content else {}


app = call("GET", f"/apps?filter[bundleId]={os.environ['BUNDLE_ID']}")["data"][0]
app_id = app["id"]

# версія App Store, яку ще редагують
versions = call("GET", f"/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=20")["data"]
ver = next((v for v in versions if v["attributes"]["appStoreState"] in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")), None)
if not ver:
    sys.exit("Немає версії App Store, яку можна редагувати")

# найновіша оброблена збірка
build = call("GET", f"/builds?filter[app]={app_id}&filter[processingState]=VALID&sort=-uploadedDate&limit=1&include=preReleaseVersion")
b = build["data"][0]
short = next(x["attributes"]["version"] for x in build.get("included", []) if x["type"] == "preReleaseVersions")
if ver["attributes"]["versionString"] != short:
    call("PATCH", f"/appStoreVersions/{ver['id']}", json={"data": {"type": "appStoreVersions", "id": ver["id"], "attributes": {"versionString": short}}})
    print(f"Версію App Store перейменовано на {short}")
# прив'язка збірки: сервер Apple іноді відповідає 500 — кілька спроб, і без неї скріншоти все одно вивантажуються
for attempt in range(3):
    r = requests.patch(f"{API}/appStoreVersions/{ver['id']}/relationships/build", headers=H, timeout=120,
                       json={"data": {"type": "builds", "id": b["id"]}})
    if r.status_code < 400:
        print(f"Збірку {b['attributes']['version']} прив'язано до версії {short} (іконка — з неї)")
        break
    time.sleep(20)
else:
    print(f"::warning::Збірку не прив'язано (Apple відповідає {r.status_code}) — можна вибрати вручну в розділі Build")

# скріншоти для кожної мови з теки
locs = {l["attributes"]["locale"]: l["id"] for l in call("GET", f"/appStoreVersions/{ver['id']}/appStoreVersionLocalizations")["data"]}
for folder in sorted(glob.glob("appstore/screenshots/*")):
    locale = os.path.basename(folder)
    files = sorted(glob.glob(f"{folder}/*.png"))
    if not files:
        continue
    if locale not in locs:
        locs[locale] = call("POST", "/appStoreVersionLocalizations", json={"data": {"type": "appStoreVersionLocalizations",
            "attributes": {"locale": locale}, "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": ver["id"]}}}}})["data"]["id"]
    lid = locs[locale]
    sets = call("GET", f"/appStoreVersionLocalizations/{lid}/appScreenshotSets")["data"]
    sset = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == DISPLAY), None)
    if sset:
        for old in call("GET", f"/appScreenshotSets/{sset['id']}/appScreenshots")["data"]:
            call("DELETE", f"/appScreenshots/{old['id']}")
    else:
        sset = call("POST", "/appScreenshotSets", json={"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": DISPLAY},
            "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": lid}}}}})["data"]
    for f in files:
        data = open(f, "rb").read()
        shot = call("POST", "/appScreenshots", json={"data": {"type": "appScreenshots",
            "attributes": {"fileName": os.path.basename(f), "fileSize": len(data)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": sset["id"]}}}}})["data"]
        for op in shot["attributes"]["uploadOperations"]:
            chunk = data[op["offset"]:op["offset"] + op["length"]]
            hdr = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
            r = requests.request(op["method"], op["url"], headers=hdr, data=chunk, timeout=120)
            if r.status_code >= 400:
                sys.exit(f"Вивантаження {f}: {r.status_code}")
        call("PATCH", f"/appScreenshots/{shot['id']}", json={"data": {"type": "appScreenshots", "id": shot["id"],
             "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    print(f"{locale}: вивантажено скріншотів — {len(files)}")
print("Готово (на перевірку нічого не подано)")
