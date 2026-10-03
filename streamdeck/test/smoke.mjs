import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import http from "node:http";
import { WebSocketServer } from "ws";

const sdPlugin = new URL("../cam.lenslink.streamdeck.sdPlugin/", import.meta.url).pathname;
const controls = [];
const state = {
	zoom: 1, maxZoom: 10, camera: "back", lens: "Main (Wide)",
	lenses: ["Ultra Wide (0.5×)", "Main (Wide)", "Telephoto (5×)"], lensFactors: [0.5, 1, 5],
	focusMode: "auto", whiteBalanceMode: "auto", exposureMode: "auto", exposureBias: 0,
	supportsWhiteBalanceLock: true, supportsManualExposure: true, iso: 100, minISO: 32, maxISO: 3200
};

const obs = http.createServer((req, res) => {
	let body = "";
	req.on("data", (d) => (body += d));
	req.on("end", () => {
		if (req.url === "/api/sources") {
			res.end(JSON.stringify({ sources: [{ id: 3, name: "Desk", connected: true, standby: false, armed: true, screen: false }] }));
		} else if (req.url === "/api/state?src=3") {
			res.end(JSON.stringify(state));
		} else if (req.url === "/api/control?src=3" && req.method === "POST") {
			controls.push(JSON.parse(body));
			res.statusCode = 204;
			res.end();
		} else {
			res.statusCode = 404;
			res.end();
		}
	});
});
await new Promise((r) => obs.listen(0, "127.0.0.1", r));

const wss = new WebSocketServer({ port: 0, host: "127.0.0.1" });
await new Promise((r) => wss.on("listening", r));
const received = [];
let socket;
const connected = new Promise((resolve) =>
	wss.on("connection", (ws) => {
		socket = ws;
		ws.on("message", (m) => {
			const msg = JSON.parse(m.toString());
			received.push(msg);
			if (msg.event === "getGlobalSettings") send({ event: "didReceiveGlobalSettings", payload: { settings: { port: String(obs.address().port) } } });
			if (msg.event === "registerPlugin") resolve();
		});
	})
);
const send = (m) => socket.send(JSON.stringify(m));

const info = {
	application: { font: "", language: "en", platform: "mac", platformVersion: "14.0", version: "7.1.0.0" },
	colors: {},
	devicePixelRatio: 2,
	devices: [{ id: "dev", name: "Stream Deck +", size: { columns: 4, rows: 2 }, type: 7 }],
	plugin: { uuid: "cam.lenslink.streamdeck", version: "0.1.0.0" }
};
const plugin = spawn(process.execPath, ["bin/plugin.js", "-port", String(wss.address().port), "-pluginUUID", "cam.lenslink.streamdeck", "-registerEvent", "registerPlugin", "-info", JSON.stringify(info)], { cwd: sdPlugin, stdio: "inherit" });

const waitFor = async (pred, what) => {
	for (let i = 0; i < 60; i++) {
		const hit = pred();
		if (hit) return hit;
		await new Promise((r) => setTimeout(r, 50));
	}
	throw new Error(`timed out waiting for ${what}`);
};
const appear = (id, context, controller, settings = {}) =>
	send({ event: "willAppear", action: `cam.lenslink.streamdeck.${id}`, context, device: "dev", payload: { controller, coordinates: { column: 0, row: 0 }, isInMultiAction: false, settings, state: 0 } });
const image = (context) => received.filter((m) => m.context === context && m.event === "setImage").map((m) => decodeURIComponent(m.payload.image)).pop() ?? "";

try {
	await connected;
	appear("camera", "cam", "Keypad");
	appear("zoom", "zoomKey", "Keypad", { zoom: "3" });
	appear("zoom", "zoomDial", "Encoder");
	appear("lock", "lock", "Keypad");
	appear("lens", "lens", "Keypad", { lens: "Ultra Wide (0.5×)" });

	await waitFor(() => image("cam").includes(">Live<"), "camera key to show Live");
	await waitFor(() => image("lens").includes(">0.5×<"), "lens key to show its factor");
	await waitFor(() => received.some((m) => m.context === "zoomDial" && m.event === "setFeedback" && m.payload.value.value === "1×"), "zoom dial feedback");

	send({ event: "keyDown", action: "cam.lenslink.streamdeck.zoom", context: "zoomKey", device: "dev", payload: { coordinates: { column: 0, row: 0 }, isInMultiAction: false, settings: { zoom: "3" }, state: 0 } });
	await waitFor(() => controls.length === 1, "zoom key command");
	assert.deepEqual(controls[0], { cmd: "zoom", value: 3 });

	send({ event: "dialRotate", action: "cam.lenslink.streamdeck.zoom", context: "zoomDial", device: "dev", payload: { controller: "Encoder", coordinates: { column: 0, row: 0 }, pressed: false, settings: {}, ticks: 2 } });
	await waitFor(() => controls.length === 2, "zoom dial command");
	assert.deepEqual(controls[1], { cmd: "zoom", value: 3.2 });

	send({ event: "keyDown", action: "cam.lenslink.streamdeck.lock", context: "lock", device: "dev", payload: { coordinates: { column: 0, row: 0 }, isInMultiAction: false, settings: {}, state: 0 } });
	await waitFor(() => controls.length === 3, "lock command");
	assert.deepEqual(controls[2], { cmd: "lock", target: "all", on: true });
	await waitFor(() => image("lock").includes(">Locked<"), "lock key to show Locked");

	send({ event: "propertyInspectorDidAppear", action: "cam.lenslink.streamdeck.lens", context: "lens", device: "dev" });
	send({ event: "sendToPlugin", action: "cam.lenslink.streamdeck.lens", context: "lens", payload: { event: "lenses" } });
	const list = await waitFor(() => received.find((m) => m.event === "sendToPropertyInspector"), "lens list");
	assert.deepEqual(list.payload.items.map((i) => i.value), ["", ...state.lenses]);

	console.log("smoke test passed");
} finally {
	plugin.kill();
	wss.close();
	obs.close();
}
