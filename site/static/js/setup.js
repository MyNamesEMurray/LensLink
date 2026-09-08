/* The setup guide filters steps rather than generating them: every step is
   in the HTML, tagged with the setups it belongs to, and answering a
   question hides the ones that don't match. With JavaScript off nothing is
   hidden and the page is still a complete, correctly ordered guide — which
   is also what search engines index.

   Answers live in the query string, so a configuration is a link. */
(function () {
	"use strict";

	var FACETS = ["os", "link", "mode", "app"];

	var form = document.getElementById("wizard");
	var guide = document.getElementById("guide");
	if (!form || !guide) return;

	var nojs = document.getElementById("nojs");
	if (nojs) nojs.hidden = true;

	/* What the chosen setup requires, beyond the obvious. */
	function needs(a) {
		var list = ["OBS Studio 32 or newer", "An iPhone or iPad on iOS 15 or later"];
		if (a.link === "usb") {
			list.push("A USB data cable — not a charge-only one");
			if (a.os === "windows") list.push("iTunes, for Apple's device driver");
		} else {
			list.push("Both devices on the same network, without client isolation");
		}
		if (a.app === "sideload") list.push("Sideloadly and an Apple ID — re-install weekly");
		if (a.app === "xcode") list.push("A Mac with Xcode and XcodeGen");
		return list;
	}

	function answers() {
		var a = {};
		FACETS.forEach(function (f) {
			var picked = form.querySelector('input[name="' + f + '"]:checked');
			if (picked) a[f] = picked.value;
		});
		return a;
	}

	/* An element is shown unless it names a facet and disagrees with the
	   answer. Steps and the paragraphs inside them are filtered alike. */
	function matches(el, a) {
		for (var i = 0; i < FACETS.length; i++) {
			var want = el.getAttribute("data-" + FACETS[i]);
			if (want && want !== a[FACETS[i]]) return false;
		}
		return true;
	}

	function apply(push) {
		var a = answers();

		var conditional = guide.querySelectorAll("[data-os], [data-link], [data-mode], [data-app]");
		Array.prototype.forEach.call(conditional, function (el) {
			el.hidden = !matches(el, a);
		});

		var box = document.getElementById("needs");
		var list = document.getElementById("needs-list");
		if (box && list) {
			list.textContent = "";
			needs(a).forEach(function (text) {
				var li = document.createElement("li");
				li.textContent = text;
				list.appendChild(li);
			});
			box.hidden = false;
		}

		if (push && window.history && window.history.replaceState) {
			var q = FACETS.map(function (f) { return f + "=" + a[f]; }).join("&");
			window.history.replaceState(null, "", "?" + q);
		}
	}

	/* Restore a shared or bookmarked configuration. */
	var params = new URLSearchParams(window.location.search);
	FACETS.forEach(function (f) {
		var value = params.get(f);
		if (!value) return;
		var input = form.querySelector('input[name="' + f + '"][value="' + value + '"]');
		if (input) input.checked = true;
	});

	form.addEventListener("change", function () { apply(true); });
	apply(params.toString().length > 0);
})();
