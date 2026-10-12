#!/usr/bin/env node
// Renders a scene JSON from tools/preview/export.luau to PNG files with three.js in headless Chromium.
//
//   node tools/preview/render.mjs scene.json out/prefix [--angles iso,front,top,close] [--size 1280x800]
//        [--focus x,y,z] [--zoom 1.5]
//   -> out/prefix_iso.png, out/prefix_front.png, ...   (angles: iso front back side top close)
//
// Setup once: (cd tools/preview && npm install). Chromium comes from PLAYWRIGHT_BROWSERS_PATH
// (playwright-core does not download browsers). Pages are served from memory (page.route), so
// there is no local web server and no network access.
import { chromium } from "playwright-core";
import { readFile, writeFile, mkdir, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const threeRoot = path.join(here, "node_modules", "three");

function usage(message) {
	if (message) console.error(message);
	console.error("usage: node tools/preview/render.mjs scene.json out_prefix [--angles iso,front,top,close] [--size 1280x800] [--focus x,y,z] [--zoom n]");
	process.exit(1);
}

const argv = process.argv.slice(2);
const [scenePath, prefix] = argv;
if (!scenePath || !prefix || scenePath.startsWith("--") || prefix.startsWith("--")) usage();
const options = { angles: ["iso", "front", "top", "close"], width: 1280, height: 800, focus: null, zoom: 1 };
for (let i = 2; i < argv.length; i += 2) {
	const flag = argv[i];
	const value = argv[i + 1];
	if (value === undefined) usage(`missing value for ${flag}`);
	if (flag === "--angles") options.angles = value.split(",").map((s) => s.trim()).filter(Boolean);
	else if (flag === "--size") {
		const [w, h] = value.toLowerCase().split("x").map(Number);
		if (!(w > 0 && h > 0)) usage(`bad --size ${value}`);
		options.width = w;
		options.height = h;
	} else if (flag === "--focus") options.focus = value.split(",").map(Number);
	else if (flag === "--zoom") options.zoom = Number(value) || 1;
	else usage(`unknown option ${flag}`);
}

const scene = JSON.parse(await readFile(scenePath, "utf8"));
if (!Array.isArray(scene.Parts) || scene.Parts.length === 0) usage(`${scenePath} has no parts`);

const html = `<!doctype html><html><head><meta charset="utf-8">
<style>html,body{margin:0;padding:0;overflow:hidden;background:#e4eaf0}canvas{display:block}</style>
<script type="importmap">{"imports":{"three":"/three/build/three.module.js","three/addons/":"/three/examples/jsm/"}}</script>
</head><body><script type="module" src="/viewer.js"></script></body></html>`;

const browser = await chromium.launch({
	args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
});
try {
	const page = await browser.newPage({ viewport: { width: options.width, height: options.height }, deviceScaleFactor: 1 });
	page.on("pageerror", (error) => console.error("[page]", error.message));
	page.on("console", (message) => {
		if (message.type() === "error") console.error("[page]", message.text());
	});
	await page.route("http://preview.local/**", async (route) => {
		const url = new URL(route.request().url());
		if (url.pathname === "/" || url.pathname === "/index.html") {
			return route.fulfill({ contentType: "text/html", body: html });
		}
		let file = null;
		if (url.pathname === "/viewer.js") file = path.join(here, "viewer.js");
		else if (url.pathname.startsWith("/three/")) {
			const resolved = path.resolve(threeRoot, decodeURIComponent(url.pathname.slice("/three/".length)));
			if (resolved.startsWith(threeRoot + path.sep)) file = resolved; // only files inside the three package
		}
		if (!file) return route.fulfill({ status: 404, body: "not found" });
		try {
			return route.fulfill({ contentType: "text/javascript", body: await readFile(file) });
		} catch {
			return route.fulfill({ status: 404, body: "not found" });
		}
	});
	await page.goto("http://preview.local/index.html");
	await page.waitForFunction(() => window.previewReady === true, null, { timeout: 60000 });
	const info = await page.evaluate((data) => window.loadScene(data), scene);
	console.log(`preview render: ${info.parts} parts in ${info.groups} batches, ${info.lights} point lights`);
	await mkdir(path.dirname(path.resolve(prefix)), { recursive: true });
	for (const angle of options.angles) {
		const url = await page.evaluate(({ angle, focus, zoom }) => window.renderView(angle, { focus, zoom }), {
			angle,
			focus: options.focus,
			zoom: options.zoom,
		});
		const file = `${prefix}_${angle}.png`;
		await writeFile(file, Buffer.from(url.slice(url.indexOf(",") + 1), "base64"));
		const { size } = await stat(file);
		console.log(`  ${file} (${Math.round(size / 1024)} KB)`);
	}
} finally {
	await browser.close();
}
