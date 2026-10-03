import streamDeck, {
	SingletonAction,
	type Action,
	type DialDownEvent,
	type DialRotateEvent,
	type DidReceiveSettingsEvent,
	type KeyDownEvent,
	type SendToPluginEvent,
	type TouchTapEvent,
	type WillAppearEvent,
	type WillDisappearEvent
} from "@elgato/streamdeck";
import { readFileSync } from "node:fs";

type JsonValue = string | number | boolean | null | undefined | JsonValue[] | { [key: string]: JsonValue };
type JsonObject = { [key: string]: JsonValue };
type Settings = JsonObject;
type State = Record<string, any>;
type Source = { id: number; name: string; connected: boolean; standby: boolean; armed: boolean; screen: boolean };
type Ctx = { a: Action<Settings>; s: Settings; src?: Source; st: State; live: boolean };
type Face = { icon: string; text: string; color?: string; on?: boolean; dim?: boolean };
type Dial = { icon: string; title: string; value: string; pct: number; dim?: boolean };
type Cmd = JsonObject | null;
type Def = {
	icon: string;
	camera?: boolean;
	key?: (c: Ctx) => Face;
	press?: (c: Ctx) => Cmd;
	dial?: (c: Ctx) => Dial;
	rotate?: (c: Ctx, ticks: number) => Cmd;
	dialPress?: (c: Ctx) => Cmd;
	tap?: (c: Ctx) => Cmd;
	lists?: Record<string, (st: State) => { label: string; value: string }[]>;
};

const GREEN = "#30D158";
const AMBER = "#FF9F0A";
const YELLOW = "#FFD60A";
const ACCENT = "#3D7BFF";
const WHITE = "#FFFFFF";
const DIM = "#5C6068";

let port = 9980;
let sources: Source[] | null = null;
const states = new Map<number, State>();
const held = new Map<number, number>();
const settings = new Map<string, Settings>();
const isoMode = new Map<string, boolean>();
let timer: NodeJS.Timeout | undefined;
let polling = false;
const shown = new Map<string, string>();

const t = (key: string) => streamDeck.i18n.t(key);
const str = (v: JsonValue | undefined, d = "") => (v === undefined || v === null ? d : String(v));
const num = (v: JsonValue | undefined, d: number) => (v === undefined || v === null || v === "" || isNaN(+v) ? d : +v);
const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
const cmp = (v: number) => String(+v.toPrecision(2));
const signed = (v: number) => (v >= 0 ? "+" : "") + v.toFixed(1);
const near = (a: unknown, b: number, tol: number) => typeof a === "number" && Math.abs(a - b) <= tol;
const base = () => `http://127.0.0.1:${port}`;

async function get(path: string): Promise<any> {
	const r = await fetch(base() + path, { signal: AbortSignal.timeout(1500) });
	if (!r.ok) throw new Error(`${path}: ${r.status}`);
	return r.json();
}

function pick(name: string) {
	return sources?.find((s) => (name ? s.name === name : !s.screen));
}

function ctx(a: Action<Settings>): Ctx {
	const s = settings.get(a.id) ?? {};
	const src = pick(str(s.source));
	const st = (src && states.get(src.id)) ?? {};
	return { a, s, src, st, live: !!src?.connected && !src.standby };
}

async function poll() {
	if (timer && !settings.size) {
		clearInterval(timer);
		timer = undefined;
		return;
	}
	if (polling) return;
	polling = true;
	try {
		sources = (await get("/api/sources")).sources;
	} catch {
		sources = null;
	}
	const ids = new Set<number>();
	for (const a of streamDeck.actions) {
		const src = pick(str(settings.get(a.id)?.source));
		if (src) ids.add(src.id);
	}
	await Promise.all(
		[...ids].map(async (id) => {
			if ((held.get(id) ?? 0) > Date.now()) return;
			try {
				states.set(id, await get(`/api/state?src=${id}`));
			} catch {
				states.delete(id);
			}
		})
	);
	polling = false;
	renderAll();
}

const glyphs = new Map<string, string>();
function glyph(name: string, color: string) {
	if (!glyphs.has(name)) {
		const svg = readFileSync(`imgs/actions/${name}.svg`, "utf8");
		glyphs.set(name, svg.slice(svg.indexOf(">") + 1, svg.lastIndexOf("</svg>")));
	}
	return `<svg viewBox="0 0 24 24" fill="none" stroke="${color}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${glyphs
		.get(name)!
		.replaceAll("#fff", color)}</svg>`;
}

const esc = (s: string) => s.replace(/[&<>"]/g, (c) => `&#${c.charCodeAt(0)};`);
const svgUrl = (svg: string) => `data:image/svg+xml;charset=utf8,${encodeURIComponent(svg)}`;

function keyImage(f: Face) {
	const color = f.dim ? DIM : f.color === ACCENT && !f.on ? WHITE : (f.color ?? WHITE);
	const ink = f.on && color === ACCENT ? WHITE : color;
	const size = Math.round(clamp(230 / Math.max(1, f.text.length), 15, 26));
	const icon = glyph(f.icon, ink).replace("<svg ", '<svg x="40" y="20" width="64" height="64" ');
	return svgUrl(
		`<svg xmlns="http://www.w3.org/2000/svg" width="144" height="144" viewBox="0 0 144 144">` +
			`<rect width="144" height="144" fill="#000"/>` +
			(f.on ? `<rect width="144" height="144" fill="${color}" fill-opacity="0.28"/>` : "") +
			icon +
			`<text x="72" y="122" text-anchor="middle" font-family="system-ui, -apple-system, 'Segoe UI', sans-serif" font-weight="600" font-size="${size}" fill="${ink}">${esc(f.text)}</text></svg>`
	);
}

function offline(c: Ctx, icon: string): Face | undefined {
	if (!c.src || !c.src.connected) return { icon, text: t("Not connected"), dim: true };
	return undefined;
}

async function render(a: Action<Settings>) {
	const def = defs[a.manifestId.split(".").pop()!];
	if (!def) return;
	const c = ctx(a);
	if (a.isKey() && def.key) {
		const f = offline(c, def.icon) ?? def.key(c);
		if (def.camera && !c.live) f.dim = true;
		const image = keyImage(f);
		if (shown.get(a.id) === image) return;
		shown.set(a.id, image);
		await a.setImage(image);
	} else if (a.isDial() && def.dial) {
		const d = def.dial(c);
		const dim = d.dim || !c.live;
		const feedback = {
			icon: svgUrl(`<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48">${glyph(d.icon, dim ? DIM : WHITE).replace("<svg ", '<svg width="48" height="48" ')}</svg>`),
			title: d.title,
			value: { value: c.live ? d.value : c.src?.connected ? d.value : t("Not connected"), color: dim ? DIM : WHITE },
			indicator: { value: clamp(Math.round(d.pct), 0, 100), bar_fill_c: dim ? DIM : YELLOW }
		};
		const key = JSON.stringify(feedback);
		if (shown.get(a.id) === key) return;
		shown.set(a.id, key);
		await a.setFeedback(feedback);
	}
}

function renderAll() {
	for (const a of streamDeck.actions) render(a).catch((e) => streamDeck.logger.warn(e));
}

function alert(a: Action<Settings>) {
	return a.isKey() || a.isDial() ? a.showAlert() : undefined;
}

async function run(c: Ctx, def: Def, cmd: Cmd, patch?: State) {
	if (!cmd || !c.src || (def.camera && !c.live)) {
		await alert(c.a);
		return;
	}
	if (patch) {
		states.set(c.src.id, Object.assign(states.get(c.src.id) ?? {}, patch));
		held.set(c.src.id, Date.now() + 1500);
	}
	try {
		const r = await fetch(`${base()}/api/control?src=${c.src.id}`, {
			method: "POST",
			body: JSON.stringify(cmd),
			signal: AbortSignal.timeout(1500)
		});
		if (!r.ok) throw new Error(String(r.status));
	} catch {
		await alert(c.a);
	}
	renderAll();
	if (!patch) setTimeout(poll, 400);
}

const patches = new WeakMap<Cmd & object, State>();
function patched(cmd: JsonObject, patch: State): Cmd {
	patches.set(cmd, patch);
	return cmd;
}

const ISOS = [25, 32, 40, 50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000, 10000, 12800, 16000, 20000, 25600];
const SHUTTERS = [1, 2, 3, 4, 5, 6, 8, 10, 13, 15, 20, 24, 25, 30, 40, 48, 50, 60, 80, 100, 120, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000];
const nearest = (list: number[], v: number) => list.reduce((b, x, i) => (Math.abs(x - v) < Math.abs(list[b] - v) ? i : b), 0);
function isoStops(st: State) {
	const lo = st.minISO || 34, hi = st.maxISO || 3072;
	const s = ISOS.filter((v) => v >= lo && v <= hi);
	return s.length > 1 ? s : [lo, hi];
}
function shutterStops(st: State) {
	const lo = Math.max(st.minShutterSeconds || 1 / 8000, 1 / 8000) * 0.999;
	const hi = (st.maxShutterSeconds || 1 / 30) * 1.001;
	const s = SHUTTERS.map((d) => 1 / d).filter((v) => v >= lo && v <= hi).reverse();
	return s.length > 1 ? s : [lo, hi];
}
const shutterLabel = (s: number) => (s >= 1 ? Math.round(s) + "s" : "1/" + Math.round(1 / s));

const front = (l: string) => /^Front/.test(l);
function lensItems(st: State) {
	const L: string[] = Array.isArray(st.lenses) ? st.lenses : [];
	const F: number[] = Array.isArray(st.lensFactors) && st.lensFactors.length === L.length ? st.lensFactors : [];
	return L.map((l, i) => ({ l, f: +F[i] || 0 }));
}
function lensText(st: State, label: string) {
	const x = lensItems(st).find((i) => i.l === label);
	return x?.f ? cmp(x.f) + "×" : label.replace(/\s*\(.*\)$/, "");
}

const groups = (st: State) => ["focus", ...(st.supportsWhiteBalanceLock ? ["whiteBalance"] : []), ...(st.supportsManualExposure ? ["exposure"] : [])];
const lockedGroup = (st: State, g: string) =>
	g === "focus" ? st.focusMode === "locked" : g === "whiteBalance" ? st.whiteBalanceMode === "locked" : st.exposureMode === "manual";
const lockModes = (g: string, on: boolean): State =>
	g === "focus" ? { focusMode: on ? "locked" : "auto" } : g === "whiteBalance" ? { whiteBalanceMode: on ? "locked" : "auto" } : { exposureMode: on ? "manual" : "auto" };

const CODEC_LABEL = (c: string) => ({ h264: "H.264", hevc: "HEVC" })[c.toLowerCase()] ?? c;
const listOf = (v: unknown) => (Array.isArray(v) ? v.map((x) => ({ label: String(x), value: String(x) })) : []);

const defs: Record<string, Def> = {
	camera: {
		icon: "camera",
		key: (c) => {
			if (c.live) return c.st.paused ? { icon: "camera", text: t("Paused"), color: AMBER, on: true } : { icon: "camera", text: t("Live"), color: GREEN, on: true };
			if (c.src?.armed) return { icon: "camera", text: t("Armed"), color: AMBER };
			return { icon: "camera", text: t("OBS connected"), color: AMBER, dim: true };
		},
		press: (c) => {
			const mode = str(c.s.press, "toggle");
			if (c.live) return mode === "start" ? null : { cmd: "stop_stream" };
			return mode !== "stop" && c.src?.armed ? { cmd: "start_stream" } : null;
		}
	},
	pause: {
		icon: "pause",
		camera: true,
		key: (c) => (c.st.paused ? { icon: "pause", text: t("Paused"), color: AMBER, on: true } : { icon: "pause", text: t("Pause") }),
		press: (c) => patched({ cmd: c.st.paused ? "resume_stream" : "pause_stream" }, { paused: !c.st.paused })
	},
	flip: {
		icon: "flip",
		camera: true,
		key: (c) => ({ icon: "flip", text: c.st.camera === "front" ? t("Front") : t("Back") }),
		press: () => ({ cmd: "flip" })
	},
	lens: {
		icon: "lens",
		camera: true,
		key: (c) => {
			const want = str(c.s.lens);
			if (!want) return { icon: "lens", text: c.st.lens ? lensText(c.st, c.st.lens) : t("Lens"), color: YELLOW };
			return { icon: "lens", text: lensText(c.st, want), color: c.st.lens === want ? YELLOW : WHITE };
		},
		press: (c) => {
			let want = str(c.s.lens);
			if (!want) {
				const cur = str(c.st.lens);
				const side = lensItems(c.st).filter((x) => front(x.l) === front(cur)).sort((a, b) => a.f - b.f);
				if (!side.length) return null;
				want = side[(side.findIndex((x) => x.l === cur) + 1) % side.length].l;
			}
			if (want === c.st.lens) return patched({ cmd: "zoom", value: 1 }, { zoom: 1 });
			return patched({ cmd: "selectLens", label: want }, { lens: want, zoom: 1 });
		},
		lists: { lenses: (st) => [{ label: "__MSG_Cycle through all__", value: "" }, ...listOf(st.lenses)] }
	},
	zoom: {
		icon: "zoom",
		camera: true,
		key: (c) => {
			const z = num(c.s.zoom, 2);
			return { icon: "zoom", text: cmp(z) + "×", color: near(c.st.zoom, z, 0.05) ? YELLOW : WHITE };
		},
		press: (c) => {
			const z = clamp(num(c.s.zoom, 2), 1, c.st.maxZoom || 10);
			return patched({ cmd: "zoom", value: z }, { zoom: z });
		},
		dial: (c) => {
			const z = +c.st.zoom || 1, max = +c.st.maxZoom || 10;
			return { icon: "zoom", title: t("Zoom"), value: cmp(z) + "×", pct: ((z - 1) / Math.max(0.01, max - 1)) * 100 };
		},
		rotate: (c, n) => {
			const z = +clamp((+c.st.zoom || 1) + n * num(c.s.step, 0.1), 1, c.st.maxZoom || 10).toFixed(2);
			return patched({ cmd: "zoom", value: z }, { zoom: z });
		},
		dialPress: () => patched({ cmd: "zoom", value: 1 }, { zoom: 1 })
	},
	flashlight: {
		icon: "flashlight",
		camera: true,
		key: (c) => ({ icon: "flashlight", text: c.st.flashlight ? t("On") : t("Off"), color: ACCENT, on: !!c.st.flashlight, dim: c.st.hasFlashlight === false }),
		press: (c) => (c.st.hasFlashlight === false ? null : patched({ cmd: "flashlight", on: !c.st.flashlight }, { flashlight: !c.st.flashlight }))
	},
	lock: {
		icon: "lock",
		camera: true,
		key: (c) => {
			const g = str(c.s.target, "all");
			const locked = g === "all" ? groups(c.st).every((x) => lockedGroup(c.st, x)) : lockedGroup(c.st, g);
			return locked ? { icon: "lock", text: t("Locked"), color: ACCENT, on: true } : { icon: "lock", text: t("Auto"), color: YELLOW };
		},
		press: (c) => {
			const g = str(c.s.target, "all");
			const gs = g === "all" ? groups(c.st) : [g];
			const on = !gs.every((x) => lockedGroup(c.st, x));
			return patched({ cmd: "lock", target: g, on }, Object.assign({}, ...gs.map((x) => lockModes(x, on))));
		}
	},
	"white-balance": {
		icon: "white-balance",
		camera: true,
		key: (c) => {
			const locked = c.st.whiteBalanceMode === "locked";
			if (str(c.s.mode, "temperature") === "auto") return { icon: "white-balance", text: t("Auto"), color: locked ? WHITE : YELLOW };
			const k = num(c.s.kelvin, 5600);
			return { icon: "white-balance", text: `${k} K`, color: locked && near(c.st.whiteBalanceTemperature, k, 50) ? YELLOW : WHITE, dim: c.st.supportsWhiteBalanceLock === false };
		},
		press: (c) => {
			if (str(c.s.mode, "temperature") === "auto") return patched({ cmd: "white_balance", mode: "auto" }, { whiteBalanceMode: "auto" });
			const k = num(c.s.kelvin, 5600);
			return patched({ cmd: "white_balance", mode: "locked", temperature: k }, { whiteBalanceMode: "locked", whiteBalanceTemperature: k });
		},
		dial: (c) => {
			const k = +c.st.whiteBalanceTemperature || 5000;
			const locked = c.st.whiteBalanceMode === "locked";
			return { icon: "white-balance", title: t("White balance"), value: locked ? `${Math.round(k)} K` : t("Auto"), pct: ((k - 2500) / 5500) * 100, dim: c.st.supportsWhiteBalanceLock === false };
		},
		rotate: (c, n) => {
			const k = clamp(Math.round(((+c.st.whiteBalanceTemperature || 5000) + n * 100) / 100) * 100, 2500, 8000);
			return patched({ cmd: "white_balance", mode: "locked", temperature: k }, { whiteBalanceMode: "locked", whiteBalanceTemperature: k });
		},
		dialPress: () => patched({ cmd: "white_balance", mode: "auto" }, { whiteBalanceMode: "auto" })
	},
	calibrate: {
		icon: "calibrate",
		camera: true,
		key: () => ({ icon: "calibrate", text: t("Calibrate") }),
		press: () => ({ cmd: "white_balance", mode: "calibrate" })
	},
	exposure: {
		icon: "exposure",
		camera: true,
		key: (c) => {
			const cur = +c.st.exposureBias || 0;
			const manual = c.st.exposureMode === "manual";
			if (str(c.s.mode, "up") === "set") {
				const v = num(c.s.value, 0);
				return { icon: "exposure", text: `${signed(v)} EV`, color: near(cur, v, 0.05) ? YELLOW : WHITE, dim: manual };
			}
			return { icon: "exposure", text: `${str(c.s.mode, "up") === "up" ? "▲" : "▼"} ${signed(cur)}`, dim: manual };
		},
		press: (c) => {
			if (c.st.exposureMode === "manual") return null;
			const mode = str(c.s.mode, "up");
			const step = num(c.s.step, 1 / 3);
			const v = mode === "set" ? num(c.s.value, 0) : clamp((+c.st.exposureBias || 0) + (mode === "up" ? step : -step), -2, 2);
			return patched({ cmd: "exposure_bias", value: +v.toFixed(2) }, { exposureBias: v });
		},
		dial: (c) => {
			const v = +c.st.exposureBias || 0;
			return { icon: "exposure", title: t("Exposure"), value: `${signed(v)} EV`, pct: ((v + 2) / 4) * 100, dim: c.st.exposureMode === "manual" };
		},
		rotate: (c, n) => {
			if (c.st.exposureMode === "manual") return null;
			const v = clamp(Math.round(((+c.st.exposureBias || 0) + n / 3) * 3) / 3, -2, 2);
			return patched({ cmd: "exposure_bias", value: +v.toFixed(2) }, { exposureBias: v });
		},
		dialPress: (c) => (c.st.exposureMode === "manual" ? null : patched({ cmd: "exposure_bias", value: 0 }, { exposureBias: 0 }))
	},
	iso: {
		icon: "iso",
		camera: true,
		dial: (c) => {
			const shutter = isoMode.get(c.a.id) === false;
			const manual = c.st.exposureMode === "manual";
			const stops = shutter ? shutterStops(c.st) : isoStops(c.st);
			const v = shutter ? +c.st.shutterSeconds || 1 / 60 : +c.st.iso || 100;
			return {
				icon: "iso",
				title: shutter ? t("Shutter") : "ISO",
				value: !manual ? t("Auto") : shutter ? shutterLabel(v) : `ISO ${Math.round(v)}`,
				pct: (nearest(stops, v) / (stops.length - 1)) * 100,
				dim: c.st.supportsManualExposure === false
			};
		},
		rotate: (c, n) => {
			if (c.st.supportsManualExposure === false) return null;
			const shutter = isoMode.get(c.a.id) === false;
			if (shutter) {
				const stops = shutterStops(c.st);
				const v = stops[clamp(nearest(stops, +c.st.shutterSeconds || 1 / 60) + n, 0, stops.length - 1)];
				return patched({ cmd: "exposure", mode: "manual", shutterSeconds: v }, { exposureMode: "manual", shutterSeconds: v });
			}
			const stops = isoStops(c.st);
			const v = stops[clamp(nearest(stops, +c.st.iso || 100) + n, 0, stops.length - 1)];
			return patched({ cmd: "exposure", mode: "manual", iso: v }, { exposureMode: "manual", iso: v });
		},
		dialPress: (c) => {
			isoMode.set(c.a.id, isoMode.get(c.a.id) === false);
			renderAll();
			return null;
		},
		tap: () => patched({ cmd: "exposure", mode: "auto" }, { exposureMode: "auto" })
	},
	focus: {
		icon: "focus",
		camera: true,
		key: (c) => {
			const locked = c.st.focusMode === "locked";
			const mode = str(c.s.mode, "faces");
			if (mode === "auto") return { icon: "focus", text: t("Auto"), color: locked ? WHITE : YELLOW };
			if (mode === "faces") return { icon: "focus", text: t("Faces"), color: ACCENT, on: !!c.st.faceFocus, dim: c.st.supportsFaceFocus === false };
			const p = num(c.s.position, 0.5);
			return { icon: "focus", text: p.toFixed(2), color: locked && near(c.st.lensPosition, p, 0.02) ? YELLOW : WHITE };
		},
		press: (c) => {
			const mode = str(c.s.mode, "faces");
			if (mode === "auto") return patched({ cmd: "focus", mode: "auto" }, { focusMode: "auto" });
			if (mode === "faces") return c.st.supportsFaceFocus === false ? null : patched({ cmd: "focus", faces: !c.st.faceFocus }, { faceFocus: !c.st.faceFocus });
			const p = clamp(num(c.s.position, 0.5), 0, 1);
			return patched({ cmd: "focus", mode: "locked", lensPosition: p }, { focusMode: "locked", lensPosition: p });
		},
		dial: (c) => {
			const p = +c.st.lensPosition || 0;
			return { icon: "focus", title: t("Focus"), value: c.st.focusMode === "locked" ? p.toFixed(2) : t("Auto"), pct: p * 100 };
		},
		rotate: (c, n) => {
			const p = +clamp((+c.st.lensPosition || 0) + n * 0.01, 0, 1).toFixed(2);
			return patched({ cmd: "focus", mode: "locked", lensPosition: p }, { focusMode: "locked", lensPosition: p });
		},
		dialPress: () => patched({ cmd: "focus", mode: "auto" }, { focusMode: "auto" })
	},
	"green-screen": {
		icon: "green-screen",
		camera: true,
		key: (c) => ({ icon: "green-screen", text: c.st.greenScreen ? t("On") : t("Off"), color: ACCENT, on: !!c.st.greenScreen, dim: !c.st.supportsGreenScreen }),
		press: (c) => {
			if (!c.st.supportsGreenScreen) return null;
			if (c.st.greenScreen) return patched({ cmd: "green_screen", on: false }, { greenScreen: false });
			return patched({ cmd: "green_screen", on: true, maxDistance: num(c.s.cutoff, -1) }, { greenScreen: true });
		}
	},
	format: {
		icon: "format",
		camera: true,
		key: (c) => {
			const r = str(c.s.resolution, "1080p"), f = num(c.s.fps, 30), k = str(c.s.codec);
			const match = c.st.resolution === r && +c.st.fps === f && (!k || str(c.st.codec).toLowerCase() === k.toLowerCase());
			return { icon: "format", text: `${r}${f}`, color: match ? YELLOW : WHITE };
		},
		press: (c) => {
			const cmd: JsonObject = { cmd: "set_format", resolution: str(c.s.resolution, "1080p"), fps: num(c.s.fps, 30) };
			if (str(c.s.codec)) cmd.codec = str(c.s.codec);
			return cmd;
		},
		lists: {
			resolutions: (st) => listOf(st.resolutions),
			frameRates: (st) => listOf(st.frameRates),
			codecs: (st) => [{ label: "__MSG_Keep current__", value: "" }, ...(Array.isArray(st.codecs) ? st.codecs.map((x: string) => ({ label: CODEC_LABEL(x), value: x })) : [])]
		}
	},
	mic: {
		icon: "mic",
		camera: true,
		key: (c) => {
			const id = str(c.s.mic);
			const mic = Array.isArray(c.st.mics) ? c.st.mics.find((m: State) => m.id === id) : undefined;
			return { icon: "mic", text: mic?.name ?? t("Mic"), color: id && c.st.mic === id ? YELLOW : WHITE, dim: !c.st.micEnabled };
		},
		press: (c) => {
			const id = str(c.s.mic);
			return id && c.st.micEnabled ? patched({ cmd: "mic", id }, { mic: id }) : null;
		},
		lists: { mics: (st) => (Array.isArray(st.mics) ? st.mics.map((m: State) => ({ label: String(m.name), value: String(m.id) })) : []) }
	}
};

class LensLinkAction extends SingletonAction<Settings> {
	override readonly manifestId: string;

	constructor(private readonly def: Def, id: string) {
		super();
		this.manifestId = `cam.lenslink.streamdeck.${id}`;
	}

	private go(a: Action<Settings>, f?: (c: Ctx) => Cmd) {
		if (!f) return;
		const c = ctx(a);
		const cmd = f(c);
		if (cmd === null && f === this.def.dialPress) return;
		run(c, this.def, cmd, cmd ? patches.get(cmd) : undefined);
	}

	override onWillAppear(ev: WillAppearEvent<Settings>) {
		settings.set(ev.action.id, ev.payload.settings);
		shown.delete(ev.action.id);
		render(ev.action);
		if (!timer) {
			timer = setInterval(poll, 1000);
			poll();
		}
	}

	override onWillDisappear(ev: WillDisappearEvent<Settings>) {
		settings.delete(ev.action.id);
		shown.delete(ev.action.id);
	}

	override onDidReceiveSettings(ev: DidReceiveSettingsEvent<Settings>) {
		settings.set(ev.action.id, ev.payload.settings);
		render(ev.action);
	}

	override onKeyDown(ev: KeyDownEvent<Settings>) {
		this.go(ev.action, this.def.press);
	}

	override onDialRotate(ev: DialRotateEvent<Settings>) {
		const rotate = this.def.rotate;
		if (rotate) this.go(ev.action, (c) => rotate(c, ev.payload.ticks));
	}

	override onDialDown(ev: DialDownEvent<Settings>) {
		this.go(ev.action, this.def.dialPress);
	}

	override onTouchTap(ev: TouchTapEvent<Settings>) {
		this.go(ev.action, this.def.tap ?? this.def.dialPress);
	}

	override async onSendToPlugin(ev: SendToPluginEvent<JsonValue, Settings>) {
		const event = str((ev.payload as JsonObject)?.event);
		const s = settings.get(ev.action.id) ?? {};
		await poll();
		let items: { label: string; value: string }[];
		if (event === "sources") {
			items = [{ label: "__MSG_First camera__", value: "" }, ...(sources ?? []).filter((x) => !x.screen).map((x) => ({ label: x.name, value: x.name }))];
		} else {
			const list = this.def.lists?.[event];
			if (!list) return;
			const src = pick(str(s.source));
			items = list((src && states.get(src.id)) ?? {});
		}
		const saved = str(s[{ sources: "source", lenses: "lens", resolutions: "resolution", frameRates: "fps", codecs: "codec", mics: "mic" }[event] ?? ""]);
		if (saved && !items.some((i) => i.value === saved)) items.push({ label: saved, value: saved });
		await streamDeck.ui.sendToPropertyInspector({ event, items });
	}
}

for (const [id, def] of Object.entries(defs)) streamDeck.actions.registerAction(new LensLinkAction(def, id));

streamDeck.settings.onDidReceiveGlobalSettings<{ port?: string }>((ev) => {
	port = num(ev.settings.port, 9980);
	poll();
});

streamDeck.connect().then(async () => {
	port = num((await streamDeck.settings.getGlobalSettings<{ port?: string }>()).port, 9980);
});
