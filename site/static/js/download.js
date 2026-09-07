/* Fills the download page from the GitHub Releases API — no server of our
   own, and no build step that would go stale between releases. Every link
   it touches already points at a working /releases/latest URL in the HTML,
   so the page is fully usable if this request fails or JavaScript is off. */
(function () {
	"use strict";

	var API = "https://api.github.com/repos/MyNamesEMurray/LensLink/releases/latest";

	/* Asset name fragment -> the row it belongs to. Matched case-insensitively
	   against the release's asset names, first match wins. */
	var ROWS = [
		["installer-windows", "win-installer"],
		["windows", "win-zip"],
		["installer-macos", "mac-pkg"],
		["macos", "mac-zip"],
		["linux", "linux"],
		["unsigned.ipa", "ipa"]
	];

	function bytes(n) {
		if (!n) return "";
		var mb = n / (1024 * 1024);
		return (mb >= 10 ? Math.round(mb) : mb.toFixed(1)) + " MB";
	}

	function detect() {
		var p = (navigator.userAgentData && navigator.userAgentData.platform) ||
			navigator.platform || "";
		var ua = navigator.userAgent || "";
		if (/Win/i.test(p) || /Windows/i.test(ua)) return "windows";
		if (/Mac/i.test(p) || /Mac OS X/i.test(ua)) {
			/* iPadOS reports as a Mac; a touch-capable "Mac" is an iPad. */
			if (navigator.maxTouchPoints > 1) return "ios";
			return "macos";
		}
		if (/iPhone|iPad|iPod/i.test(ua)) return "ios";
		if (/Linux|X11/i.test(p + ua)) return "linux";
		return "";
	}

	function highlight(os) {
		var card = document.querySelector('[data-os="' + os + '"]');
		if (!card) return;
		var btn = card.querySelector(".btn");
		if (btn) btn.classList.add("primary");
		var label = document.getElementById("os-detected");
		if (label) {
			label.textContent = card.getAttribute("data-os-name") +
				" detected — this is the build for you.";
			label.hidden = false;
		}
	}

	var os = detect();
	if (os === "ios") os = "";       /* the phone half is the same everywhere */
	if (os) highlight(os);

	fetch(API, { headers: { Accept: "application/vnd.github+json" } })
		.then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
		.then(function (rel) {
			var tag = document.getElementById("rel-tag");
			if (tag) tag.textContent = rel.tag_name;
			var when = document.getElementById("rel-date");
			if (when && rel.published_at) {
				when.textContent = new Date(rel.published_at).toLocaleDateString(undefined, {
					year: "numeric", month: "long", day: "numeric"
				});
			}
			var notes = document.getElementById("rel-notes");
			if (notes && rel.html_url) notes.href = rel.html_url;

			(rel.assets || []).forEach(function (asset) {
				var name = asset.name.toLowerCase();
				for (var i = 0; i < ROWS.length; i++) {
					var row = document.getElementById("dl-" + ROWS[i][1]);
					if (!row || row.dataset.filled) continue;
					if (name.indexOf(ROWS[i][0]) === -1) continue;
					row.dataset.filled = "1";
					var link = row.querySelector("a[href]");
					if (link) link.href = asset.browser_download_url;
					var file = row.querySelector(".file");
					if (file) {
						file.textContent = asset.name + (asset.size ? " · " + bytes(asset.size) : "");
					}
					break;
				}
			});

			var meta = document.getElementById("rel-meta");
			if (meta) meta.hidden = false;
		})
		.catch(function () {
			/* Leave the static /releases/latest links in place and say so. */
			var fallback = document.getElementById("rel-fallback");
			if (fallback) fallback.hidden = false;
		});
})();
