#!/usr/bin/env python3
"""Pick the next TestFlight build number by asking App Store Connect.

Prints `build_number=<N>` to GITHUB_OUTPUT (and stdout), where N is one
more than the highest build number ever uploaded for the app — across
every version and state, expired builds included, since ASC's uniqueness
rule spans them all.

Why ask ASC instead of counting something local: the old scheme derived
the number from GITHUB_RUN_NUMBER, which is a *per-workflow* counter —
an upload dispatched directly (run number of testflight.yml) and one
called from auto-release (run number of auto-release.yml) count in two
unrelated sequences. The first manual dispatch shipped build 1011 into a
history that was already at 1039, and TestFlight never offered it to
testers as an update because auto-update follows the highest number.
The source of truth for "highest so far" is ASC, so ask it.

If ASC can't be reached, falls back to epoch seconds: unreadable but
strictly increasing, so a degraded run can never repeat the low-number
mistake. (It can't collide upward either — a timestamp exceeds any
counter-era number, and later timestamps exceed earlier ones.)

Environment:
  ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_P8   App Store Connect API key
  BUNDLE_ID                                 app bundle id
  GITHUB_OUTPUT                             provided by Actions (optional)
"""

import os
import sys
import time
import urllib.parse

from testflight_feedback import ASC_BASE, asc_token, request


def highest_build_number(token, app_id):
    """Max numeric build number across all of the app's builds."""
    url = (f"{ASC_BASE}/v1/builds?"
           + urllib.parse.urlencode({
               "filter[app]": app_id,
               "fields[builds]": "version",
               "limit": 200,
           }))
    highest = 0
    while url:
        status, data = request(url, token)
        if status != 200:
            raise RuntimeError(f"ASC builds query -> {status}")
        for build in data.get("data", []):
            version = build.get("attributes", {}).get("version", "")
            # Numeric max, not ASC's sort order: version is a string, and
            # a lexicographic "999" would outrank "1039".
            if version.isdigit():
                highest = max(highest, int(version))
        url = (data.get("links") or {}).get("next")
    return highest


def emit(build_number, source):
    print(f"build number {build_number} ({source})")
    out = os.environ.get("GITHUB_OUTPUT")
    if out:
        with open(out, "a") as f:
            f.write(f"build_number={build_number}\n")


def main():
    bundle_id = os.environ["BUNDLE_ID"]
    try:
        token = asc_token()
        status, apps = request(
            f"{ASC_BASE}/v1/apps?"
            + urllib.parse.urlencode({"filter[bundleId]": bundle_id,
                                      "fields[apps]": "bundleId"}),
            token)
        if status != 200 or not apps.get("data"):
            raise RuntimeError(f"no app for {bundle_id} (HTTP {status})")
        highest = highest_build_number(token, apps["data"][0]["id"])
        emit(highest + 1, f"ASC reports highest existing build {highest}")
        return 0
    except Exception as e:  # noqa: BLE001 — any failure takes the fallback
        print(f"::warning::could not determine next build number from "
              f"App Store Connect ({e}) — falling back to a timestamp")
        emit(int(time.time()), "timestamp fallback")
        return 0


if __name__ == "__main__":
    sys.exit(main())
