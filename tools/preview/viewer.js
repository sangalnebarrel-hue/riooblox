// Page side of tools/preview/render.mjs: builds a three.js scene from an export.luau scene JSON and
// renders camera views to PNG data URLs. Coordinates are Roblox's (right handed, +Y up, a camera
// looks along -Z), which three.js shares, so CFrame components map straight onto Matrix4.
import * as THREE from "three";
import { RoomEnvironment } from "three/addons/environments/RoomEnvironment.js";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";

const W = window.innerWidth;
const H = window.innerHeight;
const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(1);
renderer.setSize(W, H);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 0.9;
document.body.appendChild(renderer.domElement);

const scene = new THREE.Scene();
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
scene.environmentIntensity = 0.45;

// Soft studio backdrop: a vertical gradient.
{
	const c = document.createElement("canvas");
	c.width = 4;
	c.height = 256;
	const g = c.getContext("2d");
	const grad = g.createLinearGradient(0, 0, 0, 256);
	grad.addColorStop(0, "#b9c9da");
	grad.addColorStop(0.6, "#e4eaf0");
	grad.addColorStop(1, "#f3f1ec");
	g.fillStyle = grad;
	g.fillRect(0, 0, 4, 256);
	const tex = new THREE.CanvasTexture(c);
	tex.colorSpace = THREE.SRGBColorSpace;
	scene.background = tex;
}

// Roblox materials -> roughness / metalness (colour comes from the part).
const SURFACE = {
	Plastic: [0.62, 0], SmoothPlastic: [0.42, 0], Wood: [0.82, 0], WoodPlanks: [0.84, 0], Slate: [0.9, 0],
	Granite: [0.8, 0], Marble: [0.3, 0], Concrete: [0.95, 0], Brick: [0.95, 0], Grass: [1, 0], LeafyGrass: [1, 0],
	Sand: [1, 0], Snow: [0.9, 0], Ice: [0.12, 0], Glacier: [0.15, 0], Basalt: [0.95, 0], CrackedLava: [0.9, 0],
	Cobblestone: [0.95, 0], Rock: [0.95, 0], Pebble: [0.9, 0], Fabric: [1, 0], Asphalt: [0.95, 0], Mud: [1, 0],
	Ground: [1, 0], Limestone: [0.9, 0], Pavement: [0.9, 0], Salt: [0.85, 0], Sandstone: [0.92, 0], Cardboard: [0.95, 0],
	Carpet: [1, 0], CeramicTiles: [0.35, 0], ClayRoofTiles: [0.8, 0], RoofShingles: [0.9, 0], Leather: [0.6, 0],
	Plaster: [0.95, 0], Rubber: [0.9, 0], Foil: [0.25, 0.9], Metal: [0.38, 0.85], DiamondPlate: [0.32, 0.9],
	CorrodedMetal: [0.72, 0.6],
};
const GLOW = { Neon: true, ForceField: true };

const unit = {
	box: new THREE.BoxGeometry(1, 1, 1),
	ball: new THREE.SphereGeometry(0.5, 40, 20),
	cylinder: new THREE.CylinderGeometry(0.5, 0.5, 1, 40).rotateZ(-Math.PI / 2), // axis X, as in Roblox
	wedge: convex([
		[-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [0.5, -0.5, 0.5], [-0.5, -0.5, 0.5], [0.5, 0.5, 0.5], [-0.5, 0.5, 0.5],
	], [[0, 1, 2], [0, 2, 3], [2, 3, 5], [2, 5, 4], [0, 1, 4], [0, 4, 5], [0, 3, 5], [1, 2, 4]]),
	// Peak at (+X, +Y, -Z), sloping down towards -X and +Z.
	cornerWedge: convex([
		[-0.5, -0.5, -0.5], [0.5, -0.5, -0.5], [0.5, -0.5, 0.5], [-0.5, -0.5, 0.5], [0.5, 0.5, -0.5],
	], [[0, 1, 2], [0, 2, 3], [1, 2, 4], [0, 1, 4], [4, 3, 0], [4, 2, 3]]),
};

// A flat-shaded convex solid; every triangle is turned to face away from the centroid.
function convex(points, triangles) {
	const centre = new THREE.Vector3();
	const p = points.map((v) => new THREE.Vector3(...v));
	p.forEach((v) => centre.add(v));
	centre.divideScalar(p.length);
	const positions = [];
	for (const [a, b, c] of triangles) {
		const n = new THREE.Vector3().subVectors(p[b], p[a]).cross(new THREE.Vector3().subVectors(p[c], p[a]));
		const mid = new THREE.Vector3().add(p[a]).add(p[b]).add(p[c]).divideScalar(3).sub(centre);
		const order = n.dot(mid) < 0 ? [a, c, b] : [a, b, c];
		for (const i of order) positions.push(p[i].x, p[i].y, p[i].z);
	}
	const g = new THREE.BufferGeometry();
	g.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
	g.computeVertexNormals();
	return g;
}

function cframeMatrix(c) {
	const m = new THREE.Matrix4();
	m.set(c[3], c[4], c[5], c[0], c[6], c[7], c[8], c[1], c[9], c[10], c[11], c[2], 0, 0, 0, 1);
	return m;
}

function shapeOf(part) {
	if (part.Class === "WedgePart") return "wedge";
	if (part.Class === "CornerWedgePart") return "cornerWedge";
	if (part.Class === "TrussPart") return "truss";
	if (part.Shape === "Ball") return "ball";
	if (part.Shape === "Cylinder") return "cylinder";
	return "box";
}

function partMatrix(part, shape) {
	const [sx, sy, sz] = part.Size;
	let scale;
	if (shape === "ball") {
		const d = Math.min(sx, sy, sz);
		scale = new THREE.Vector3(d, d, d);
	} else if (shape === "cylinder") {
		const d = Math.min(sy, sz);
		scale = new THREE.Vector3(sx, d, d);
	} else {
		scale = new THREE.Vector3(sx, sy, sz);
	}
	return cframeMatrix(part.CFrame).multiply(new THREE.Matrix4().makeScale(scale.x, scale.y, scale.z));
}

// One shared material per look; colours come per instance.
const materials = new Map();
function materialFor(name, transparency, reflectance, approx) {
	const t = Math.round(Math.min(1, Math.max(0, transparency)) * 20) / 20;
	const r = Math.round(Math.min(1, Math.max(0, reflectance)) * 10) / 10;
	const key = `${name}|${t}|${r}|${approx ? 1 : 0}`;
	if (materials.has(key)) return materials.get(key);
	let mat;
	if (name === "Neon") {
		mat = new THREE.MeshBasicMaterial({ color: 0xffffff, toneMapped: false, transparent: t > 0, opacity: 1 - t * 0.9 });
	} else if (name === "ForceField") {
		mat = new THREE.MeshBasicMaterial({
			color: 0xffffff, transparent: true, opacity: Math.max(0.08, 0.45 * (1 - t)), blending: THREE.AdditiveBlending,
			depthWrite: false, side: THREE.DoubleSide, toneMapped: false,
		});
	} else if (name === "Glass") {
		mat = new THREE.MeshPhysicalMaterial({
			color: 0xffffff, roughness: 0.04, metalness: 0, transparent: true, opacity: 0.2 + 0.6 * (1 - t),
			clearcoat: 1, clearcoatRoughness: 0.05, envMapIntensity: 1.6, depthWrite: false, side: THREE.DoubleSide,
		});
	} else {
		const [rough, metal] = SURFACE[name] || SURFACE.Plastic;
		mat = new THREE.MeshStandardMaterial({
			color: 0xffffff,
			roughness: rough * (1 - r * 0.8),
			metalness: Math.min(1, metal + r * 0.5),
			envMapIntensity: 1 + r * 2,
			transparent: t > 0 || approx,
			opacity: (1 - t) * (approx ? 0.75 : 1),
			depthWrite: t < 0.5,
		});
		if (name === "CrackedLava") {
			mat.emissive = new THREE.Color(0.35, 0.08, 0.02);
		}
	}
	materials.set(key, mat);
	return mat;
}

// Trusses: four rails and cross bars every 2 studs along the long axis (drawn individually).
function trussMesh(part, colour) {
	const group = new THREE.Group();
	const mat = new THREE.MeshStandardMaterial({ color: colour, roughness: 0.4, metalness: 0.8 });
	const size = part.Size;
	const axis = size.indexOf(Math.max(...size));
	const length = size[axis];
	const w = [size[(axis + 1) % 3], size[(axis + 2) % 3]];
	const rail = 0.22;
	const add = (centre, dims) => {
		const m = new THREE.Mesh(unit.box, mat);
		const s = [0, 0, 0];
		s[axis] = dims[0];
		s[(axis + 1) % 3] = dims[1];
		s[(axis + 2) % 3] = dims[2];
		m.scale.set(s[0], s[1], s[2]);
		const p = [0, 0, 0];
		p[axis] = centre[0];
		p[(axis + 1) % 3] = centre[1];
		p[(axis + 2) % 3] = centre[2];
		m.position.set(p[0], p[1], p[2]);
		m.castShadow = true;
		m.receiveShadow = true;
		group.add(m);
	};
	for (const a of [-1, 1]) for (const b of [-1, 1]) add([0, (a * (w[0] - rail)) / 2, (b * (w[1] - rail)) / 2], [length, rail, rail]);
	for (let x = -length / 2 + 1; x < length / 2; x += 2) {
		for (const a of [-1, 1]) {
			add([x, (a * (w[0] - rail)) / 2, 0], [rail, rail, w[1]]);
			add([x, 0, (a * (w[1] - rail)) / 2], [rail, w[0], rail]);
		}
	}
	group.matrixAutoUpdate = false;
	group.matrix.copy(cframeMatrix(part.CFrame));
	return group;
}

let bounds = null;
const sunTarget = new THREE.Object3D();
scene.add(sunTarget);

window.loadScene = function (data) {
	const groups = new Map();
	const neonBoost = 4; // well above the bloom threshold, like Roblox neon
	for (const part of data.Parts) {
		const shape = shapeOf(part);
		const colour = new THREE.Color(part.Color[0], part.Color[1], part.Color[2]).convertSRGBToLinear();
		if (shape === "truss") {
			scene.add(trussMesh(part, colour));
			continue;
		}
		const mat = materialFor(part.Material, part.Transparency || 0, part.Reflectance || 0, !!part.Approx);
		const key = `${shape}|${mat.uuid}`;
		if (!groups.has(key)) groups.set(key, { shape, mat, parts: [] });
		if (part.Material === "Neon") colour.multiplyScalar(neonBoost);
		groups.get(key).parts.push({ part, colour });
	}
	for (const { shape, mat, parts } of groups.values()) {
		const mesh = new THREE.InstancedMesh(unit[shape], mat, parts.length);
		parts.forEach(({ part, colour }, i) => {
			mesh.setMatrixAt(i, partMatrix(part, shape));
			mesh.setColorAt(i, colour);
		});
		const opaque = !mat.transparent && !GLOW[mat.name];
		mesh.castShadow = opaque && mat.type !== "MeshBasicMaterial";
		mesh.receiveShadow = mat.type !== "MeshBasicMaterial";
		if (mat.transparent) mesh.renderOrder = 1;
		scene.add(mesh);
	}

	const min = new THREE.Vector3(...(data.Bounds ? data.Bounds.Min : [-10, 0, -10]));
	const max = new THREE.Vector3(...(data.Bounds ? data.Bounds.Max : [10, 10, 10]));
	bounds = new THREE.Box3(min, max);
	const size = bounds.getSize(new THREE.Vector3());
	const centre = bounds.getCenter(new THREE.Vector3());
	const extent = Math.max(size.x, size.z, 8);

	scene.add(new THREE.HemisphereLight(0xf4f8ff, 0x8a8478, 0.7));
	const sun = new THREE.DirectionalLight(0xfff4e2, 2.1);
	const reach = Math.max(size.length(), 20);
	sun.position.copy(centre).add(new THREE.Vector3(0.55, 1, -0.35).normalize().multiplyScalar(reach * 1.5));
	sunTarget.position.copy(centre);
	sun.target = sunTarget;
	sun.castShadow = true;
	sun.shadow.mapSize.set(2048, 2048);
	const cam = sun.shadow.camera;
	cam.left = cam.bottom = -reach * 0.75;
	cam.right = cam.top = reach * 0.75;
	cam.near = 0.5;
	cam.far = reach * 4;
	sun.shadow.bias = -0.0004;
	sun.shadow.normalBias = 0.02;
	sun.shadow.radius = 4;
	scene.add(sun);

	// The scene's own point lights (brightest few; three.js cost grows with every light).
	// Lune's serde writes an empty list as {}.
	const lights = (Array.isArray(data.Lights) ? data.Lights : []).slice().sort((a, b) => b.Brightness * b.Range - a.Brightness * a.Range).slice(0, 8);
	for (const l of lights) {
		const light = new THREE.PointLight(new THREE.Color(...l.Color), l.Brightness * 4, l.Range * 1.3, 1.4);
		light.position.set(...l.Position);
		scene.add(light);
	}

	// Ground: a shadow catcher and a 4-stud grid just under the lowest part.
	const groundSize = Math.ceil((extent * 1.8) / 4) * 4;
	const ground = new THREE.Mesh(new THREE.PlaneGeometry(groundSize * 3, groundSize * 3), new THREE.MeshStandardMaterial({ color: 0xc9ccce, roughness: 1 }));
	ground.rotation.x = -Math.PI / 2;
	ground.position.set(centre.x, min.y - 0.06, centre.z);
	ground.receiveShadow = true;
	scene.add(ground);
	const grid = new THREE.GridHelper(groundSize, groundSize / 4, 0x7d8690, 0xa9b0b7);
	grid.position.set(centre.x, min.y - 0.04, centre.z);
	scene.add(grid);
	return { parts: data.Parts.length, groups: groups.size, lights: lights.length };
};

const camera = new THREE.PerspectiveCamera(35, W / H, 0.1, 20000);
let composer = null;
function compose() {
	if (composer) return composer;
	const target = new THREE.WebGLRenderTarget(W, H, { type: THREE.HalfFloatType, samples: 4 });
	composer = new EffectComposer(renderer, target);
	composer.addPass(new RenderPass(scene, camera));
	composer.addPass(new UnrealBloomPass(new THREE.Vector2(W, H), 0.6, 0.5, 2.2)); // only neon / glow passes 2.2
	composer.addPass(new OutputPass());
	return composer;
}

// Distance at which every corner of the bounds projects inside 90 % of the frame (binary search).
function fitDistance(dir, target, up) {
	const corners = [];
	for (const x of [bounds.min.x, bounds.max.x]) for (const y of [bounds.min.y, bounds.max.y]) for (const z of [bounds.min.z, bounds.max.z]) corners.push(new THREE.Vector3(x, y, z));
	const fits = (d) => {
		camera.position.copy(target).addScaledVector(dir, d);
		camera.up.copy(up);
		camera.near = Math.max(0.05, d / 500);
		camera.far = d * 20;
		camera.lookAt(target);
		camera.updateMatrixWorld();
		camera.updateProjectionMatrix();
		return corners.every((c) => {
			const v = c.clone().applyMatrix4(camera.matrixWorldInverse);
			if (v.z > -camera.near) return false; // behind the camera
			const p = c.clone().project(camera);
			return Math.abs(p.x) <= 0.9 && Math.abs(p.y) <= 0.9;
		});
	};
	let lo = 0.1;
	let hi = Math.max(bounds.getSize(new THREE.Vector3()).length(), 4) * 20;
	for (let i = 0; i < 40; i++) {
		const mid = (lo + hi) / 2;
		if (fits(mid)) hi = mid;
		else lo = mid;
	}
	return hi;
}

// angle: iso | front | top | close | back | side. options: {focus:[x,y,z], zoom:n}
window.renderView = function (angle, options = {}) {
	const target = options.focus ? new THREE.Vector3(...options.focus) : bounds.getCenter(new THREE.Vector3());
	const dirs = {
		iso: [1, 0.8, -1], // front right, from above (the front is -Z)
		front: [0, 0.22, -1],
		back: [0, 0.22, 1],
		side: [1, 0.22, 0],
		top: [0, 1, 0],
		close: [-1, 0.55, -1.2],
	};
	const dir = new THREE.Vector3(...(dirs[angle] || dirs.iso)).normalize();
	const up = angle === "top" ? new THREE.Vector3(0, 0, -1) : new THREE.Vector3(0, 1, 0);
	let distance = fitDistance(dir, target, up);
	if (angle === "close") distance *= 0.55;
	distance /= options.zoom || 1;
	camera.up.copy(up);
	camera.position.copy(target).addScaledVector(dir, distance);
	camera.near = Math.max(0.05, distance / 500);
	camera.far = distance * 20;
	camera.lookAt(target);
	camera.updateProjectionMatrix();
	compose().render();
	return renderer.domElement.toDataURL("image/png");
};

window.previewReady = true;
