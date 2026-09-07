/* Small progressive enhancements: the small-screen menu and the
   on-page contents highlight. Every page works with JavaScript off. */
(function () {
	"use strict";

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
		toggle.textContent = "All documentation pages";
		side.classList.add("collapsed");
		side.insertBefore(toggle, side.firstChild);
		toggle.addEventListener("click", function () {
			var open = !side.classList.toggle("collapsed");
			toggle.setAttribute("aria-expanded", open ? "true" : "false");
		});
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
