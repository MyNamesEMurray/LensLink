/* Small progressive enhancements: the small-screen menu and the
   on-page contents highlight. Every page works with JavaScript off. */
(function () {
	"use strict";

	var strings = {};
	try {
		strings = JSON.parse(document.getElementById("i18n").textContent) || {};
	} catch (e) { strings = {}; }
	function t(key, fallback) {
		return typeof strings[key] === "string" && strings[key] ? strings[key] : fallback;
	}

	var menu = document.querySelector(".menu");
	var drop = document.getElementById("sitenav");
	if (menu && drop) {
		menu.addEventListener("click", function () {
			var open = drop.classList.toggle("open");
			menu.setAttribute("aria-expanded", open ? "true" : "false");
		});
	}

	/* On a narrow screen the sidebar's twelve links push the page's own
	   heading a full screen down, so collapse it behind a toggle. Without
	   JavaScript the list simply stays expanded, which is still usable. */
	var side = document.querySelector(".side");
	if (side && window.matchMedia("(max-width: 860px)").matches) {
		var toggle = document.createElement("button");
		toggle.className = "sidetoggle";
		toggle.type = "button";
		toggle.setAttribute("aria-expanded", "false");
		toggle.textContent = t("docs.all_pages", "All documentation pages");
		side.classList.add("collapsed");
		side.insertBefore(toggle, side.firstChild);
		toggle.addEventListener("click", function () {
			var open = !side.classList.toggle("collapsed");
			toggle.setAttribute("aria-expanded", open ? "true" : "false");
		});
	}

	var pick = document.querySelector(".langpick");
	if (pick) {
		document.addEventListener("click", function (e) {
			if (pick.open && !pick.contains(e.target)) pick.open = false;
		});
		pick.addEventListener("keydown", function (e) {
			if (e.key === "Escape" && pick.open) {
				pick.open = false;
				pick.querySelector("summary").focus();
			}
		});
	}

	var DISMISSED = "lenslink.lang-suggest";
	function dismissed() {
		try { return window.localStorage.getItem(DISMISSED) === "1"; } catch (e) { return false; }
	}
	function suggestion() {
		var root = (document.documentElement.lang || "").toLowerCase();
		if (root !== "en" && root.indexOf("en-") !== 0) return null;
		var offers = [].slice.call(document.querySelectorAll(".langs a[data-suggest]"));
		if (!offers.length || dismissed()) return null;
		var prefs = navigator.languages && navigator.languages.length ?
			navigator.languages : [navigator.language || ""];
		for (var i = 0; i < prefs.length; i++) {
			var want = String(prefs[i] || "").toLowerCase();
			var primary = want.split("-")[0];
			if (!primary || primary === "en") return null;
			if (primary === "zh" && /^zh-(tw|hk|mo)\b|hant/.test(want)) continue;
			var loose = null;
			for (var j = 0; j < offers.length; j++) {
				var code = (offers[j].getAttribute("hreflang") || "").toLowerCase();
				if (code === want) return offers[j];
				if (!loose && code.split("-")[0] === primary) loose = offers[j];
			}
			if (loose) return loose;
		}
		return null;
	}
	var offer = suggestion();
	if (offer) {
		var bar = document.createElement("div");
		bar.className = "langbar";
		bar.lang = offer.getAttribute("lang") || "";
		var go = document.createElement("a");
		go.href = offer.getAttribute("href");
		go.hreflang = offer.getAttribute("hreflang") || "";
		go.textContent = offer.getAttribute("data-suggest");
		var close = document.createElement("button");
		close.type = "button";
		close.setAttribute("aria-label", offer.getAttribute("data-dismiss") || "Dismiss");
		close.textContent = "\u00d7";
		close.addEventListener("click", function () {
			try { window.localStorage.setItem(DISMISSED, "1"); } catch (e) {}
			bar.parentNode.removeChild(bar);
		});
		bar.appendChild(go);
		bar.appendChild(close);
		document.body.appendChild(bar);
	}

	var links = [].slice.call(document.querySelectorAll(".toc a"));
	if (!links.length || !("IntersectionObserver" in window)) return;

	var byId = {};
	links.forEach(function (a) { byId[a.getAttribute("href").slice(1)] = a; });

	var seen = [];
	var observer = new IntersectionObserver(function (entries) {
		entries.forEach(function (entry) {
			var id = entry.target.id;
			var i = seen.indexOf(id);
			if (entry.isIntersecting && i < 0) seen.push(id);
			if (!entry.isIntersecting && i >= 0) seen.splice(i, 1);
		});
		if (!seen.length) return;
		var order = Object.keys(byId);
		var top = seen.slice().sort(function (a, b) {
			return order.indexOf(a) - order.indexOf(b);
		})[0];
		links.forEach(function (a) {
			a.classList.toggle("on", a.getAttribute("href") === "#" + top);
		});
	}, { rootMargin: "-80px 0px -70% 0px" });

	Object.keys(byId).forEach(function (id) {
		var el = document.getElementById(id);
		if (el) observer.observe(el);
	});
})();
