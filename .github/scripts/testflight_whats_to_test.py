#!/usr/bin/env python3
"""Populate "What to Test" and distribute the uploaded TestFlight build.

Runs right after the TestFlight upload: waits for App Store Connect to
finish processing the build (matched by CFBundleVersion), writes the
latest GitHub release's "What's Changed" section — converted to plain
text — into the build's betaBuildLocalizations `whatsToTest` attribute
(exactly what testers see under "What to Test" in the TestFlight app),
then assigns the build to the beta groups named in ASC_BETA_GROUPS.
External groups are submitted for beta app review automatically — the
first build of a version waits on Apple, later ones clear quickly.

Environment:
  ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_P8   App Store Connect API key
  BUNDLE_ID                                 app bundle id
  BUILD_NUMBER                              CFBundleVersion just uploaded
  ASC_BETA_GROUPS                           comma-separated TestFlight
                                            group names (unset = skip)
  GITHUB_TOKEN / GITHUB_REPOSITORY          provided by Actions
"""

import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from testflight_feedback import ASC_BASE, asc_get, asc_token, gh, request

MAX_LEN = 4000        # ASC limit for whatsToTest
POLL_SECONDS = 60
POLL_LIMIT = 30       # ~30 min; processing usually takes 5-15


def release_notes(repo):
    """Latest release's tag + the changelog part of its body."""
    status, rel = gh(f"/repos/{repo}/releases/latest")
    if status != 200:
        return "", ""
    body = rel.get("body") or ""
    # The release body is install boilerplate followed by the
    # auto-generated "What's Changed" section; testers only need the
    # second part.
    m = re.search(r"^#+\s*What's Changed\s*$", body, re.M | re.I)
    if m:
        body = body[m.end():]
    return rel.get("tag_name") or "", body


def plain_text(md):
    """Markdown → the plain text TestFlight displays."""
    out = []
    for line in md.splitlines():
        line = line.strip()
        if re.match(r"\**Full Changelog", line, re.I):
            continue
        line = re.sub(r"^#+\s*", "", line)                     # headers
        line = re.sub(r"^[*-]\s+", "• ", line)                 # bullets
        line = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", line)   # links
        line = line.replace("**", "").replace("`", "")
        out.append(line)
    return re.sub(r"\n{3,}", "\n\n", "\n".join(out)).strip()


def assign_groups(app_id, build_id, token):
    """Distribute the build to the beta groups named in ASC_BETA_GROUPS."""
    names = [n.strip()
             for n in os.environ.get("ASC_BETA_GROUPS", "").split(",")
             if n.strip()]
    if not names:
        print("ASC_BETA_GROUPS not set — skipping test-group assignment")
        return True

    ok = True
    groups = []
    for name in names:
        found = asc_get("/v1/betaGroups", token,
                        **{"filter[app]": app_id, "filter[name]": name,
                           "fields[betaGroups]": "name,isInternalGroup"})
        data = (found or {}).get("data", [])
        if not data:
            print(f"::warning::beta group \"{name}\" not found — "
                  f"check the ASC_BETA_GROUPS repository variable")
            ok = False
            continue
        groups.append(data[0])

    # External groups only get builds that passed beta app review; submit
    # before assigning (fastlane's order). Internal groups need neither.
    if any(not g.get("attributes", {}).get("isInternalGroup")
           for g in groups):
        status, resp = request(
            f"{ASC_BASE}/v1/betaAppReviewSubmissions", token, method="POST",
            body={"data": {"type": "betaAppReviewSubmissions",
                           "relationships": {"build": {"data": {
                               "type": "builds", "id": build_id}}}}})
        if status == 201:
            print("submitted for beta app review")
        elif status in (409, 422):
            # Already submitted or already approved — both fine.
            print(f"beta review submission not needed ({status})")
        else:
            print(f"::warning::beta review submission failed ({status}): "
                  f"{str(resp)[:300]}")
            ok = False

    for group in groups:
        name = group.get("attributes", {}).get("name", group["id"])
        status, resp = request(
            f"{ASC_BASE}/v1/betaGroups/{group['id']}/relationships/builds",
            token, method="POST",
            body={"data": [{"type": "builds", "id": build_id}]})
        if status in (200, 201, 204):
            print(f"build added to test group \"{name}\"")
        else:
            print(f"::warning::adding build to group \"{name}\" "
                  f"failed ({status}): {str(resp)[:300]}")
            ok = False
    return ok


def main():
    repo = os.environ["GITHUB_REPOSITORY"]
    bundle_id = os.environ["BUNDLE_ID"]
    build_number = os.environ["BUILD_NUMBER"]

    tag, body = release_notes(repo)
    notes = plain_text(body) or "General improvements and bug fixes."
    text = (f"Changes in this build ({tag or 'latest'}):\n\n" + notes)[:MAX_LEN]

    token = asc_token()
    apps = asc_get("/v1/apps", token, **{"filter[bundleId]": bundle_id,
                                         "fields[apps]": "bundleId"})
    if not apps or not apps.get("data"):
        print(f"::warning::no app found for bundle id {bundle_id}")
        return 1
    app_id = apps["data"][0]["id"]

    # The upload finishes before ASC registers the build, and group
    # assignment needs processing to have finished too — poll until the
    # build is VALID. Tokens live ~10 min, so mint a fresh one per attempt.
    build_id = None
    for attempt in range(POLL_LIMIT):
        token = asc_token()
        builds = asc_get("/v1/builds", token,
                         **{"filter[app]": app_id,
                            "filter[version]": build_number,
                            "fields[builds]": "processingState", "limit": 1})
        data = (builds or {}).get("data", [])
        state = data[0]["attributes"]["processingState"] if data else "not registered"
        if state == "VALID":
            build_id = data[0]["id"]
            break
        if state in ("FAILED", "INVALID"):
            print(f"::warning::build {build_number} processing "
                  f"ended in {state} — nothing to distribute")
            return 1
        print(f"build {build_number}: {state} "
              f"({attempt + 1}/{POLL_LIMIT}) — retrying in {POLL_SECONDS}s")
        time.sleep(POLL_SECONDS)
    if not build_id:
        print("::warning::build never finished processing in App Store "
              "Connect — set What to Test / groups manually")
        return 1

    ok = True
    locs = asc_get(f"/v1/builds/{build_id}/betaBuildLocalizations", token)
    existing = (locs or {}).get("data", [])
    if existing:
        loc_id = existing[0]["id"]
        status, resp = request(
            f"{ASC_BASE}/v1/betaBuildLocalizations/{loc_id}", token,
            method="PATCH",
            body={"data": {"type": "betaBuildLocalizations", "id": loc_id,
                           "attributes": {"whatsToTest": text}}})
    else:
        status, resp = request(
            f"{ASC_BASE}/v1/betaBuildLocalizations", token, method="POST",
            body={"data": {"type": "betaBuildLocalizations",
                           "attributes": {"whatsToTest": text,
                                          "locale": "en-US"},
                           "relationships": {"build": {"data": {
                               "type": "builds", "id": build_id}}}}})
    if status in (200, 201):
        print(f"What to Test set for build {build_number} "
              f"({len(text)} chars, from {tag or 'latest release'})")
    else:
        print(f"::warning::setting What to Test failed ({status}): "
              f"{str(resp)[:300]}")
        ok = False

    # Even if the notes failed, still try to distribute the build.
    if not assign_groups(app_id, build_id, token):
        ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
