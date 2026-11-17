import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import botBytes from './mini_bot.glb';

const $ = (id) => document.getElementById(id);
const screenEl = $('screen');
const canvas = $('gl');

/* ---------- renderer, camera ---------- */
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;

const scene = new THREE.Scene();
scene.background = new THREE.Color('#171923');
scene.fog = new THREE.Fog('#171923', 20, 34);

const camera = new THREE.PerspectiveCamera(36, 852 / 480, 0.1, 100);
camera.position.set(0, 7.6, 10.6);
const controls = new OrbitControls(camera, canvas);
controls.target.set(0, 0.7, -0.3);
controls.enablePan = false;
controls.enableDamping = true;
controls.dampingFactor = 0.08;
controls.minDistance = 7;
controls.maxDistance = 15;
controls.minPolarAngle = 0.45;
controls.maxPolarAngle = 1.3;
controls.minAzimuthAngle = -0.95;
controls.maxAzimuthAngle = 0.95;
controls.update();
controls.saveState();

function resize() {
  const w = screenEl.clientWidth, h = screenEl.clientHeight;
  if (!w || !h) return;
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
}
new ResizeObserver(resize).observe(screenEl);
resize();

/* ---------- lights ---------- */
scene.add(new THREE.HemisphereLight('#fff1dc', '#5a4a3c', 1.3));
const sun = new THREE.DirectionalLight('#ffe2b8', 1.6);
sun.position.set(4, 8, 5);
scene.add(sun);
const windowLight = new THREE.PointLight('#9fb4ff', 5, 7, 2);
windowLight.position.set(0, 2, -2.6);
scene.add(windowLight);

/* ---------- room helpers ---------- */
const M = (c, o = {}) => new THREE.MeshStandardMaterial({ color: c, roughness: 0.85, metalness: 0, flatShading: true, ...o });
function add(geo, mat, x, y, z) { const m = new THREE.Mesh(geo, mat); m.position.set(x, y, z); scene.add(m); return m; }
const box = (w, h, d, c, x, y, z, o) => add(new THREE.BoxGeometry(w, h, d), M(c, o), x, y, z);
const cyl = (rt, rb, h, c, x, y, z, seg = 16, o) => add(new THREE.CylinderGeometry(rt, rb, h, seg), M(c, o), x, y, z);

function canvasTex(w, h, draw) {
  const c = document.createElement('canvas'); c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; return t;
}

/* ---------- the room (original) ---------- */
// floor: 9 x 7 tiles, one tile = one world unit
for (let i = 0; i < 9; i++) for (let j = 0; j < 7; j++) {
  box(1, 0.2, 1, (i + j) % 2 ? '#c99c6c' : '#bd8f60', -4 + i, -0.1, -3 + j);
}
box(9.4, 0.5, 7.4, '#5b4636', 0, -0.45, 0);
// walls (cutaway diorama: back and left only)
box(9, 3.2, 0.2, '#efe3cc', 0, 1.6, -3.6);
box(0.2, 3.2, 7.2, '#e6d7bd', -4.6, 1.6, 0);
box(9, 0.18, 0.06, '#a77d57', 0, 0.09, -3.47);
box(0.06, 0.18, 7, '#a77d57', -4.47, 0.09, 0);
box(9.2, 0.12, 0.3, '#a77d57', 0, 3.26, -3.6);
box(0.3, 0.12, 7.4, '#a77d57', -4.6, 3.26, 0);

// window with the moon
box(1.9, 1.4, 0.1, '#7a5a42', 0, 1.95, -3.48);
box(1.6, 1.1, 0.05, '#1b2546', 0, 1.95, -3.42, { emissive: '#1b2546', emissiveIntensity: 0.7 });
box(0.06, 1.1, 0.06, '#7a5a42', 0, 1.95, -3.39);
box(1.6, 0.06, 0.06, '#7a5a42', 0, 1.95, -3.39);
box(2.1, 0.08, 0.28, '#7a5a42', 0, 1.22, -3.38);
add(new THREE.SphereGeometry(0.13, 16, 12), M('#ffe3a3', { emissive: '#ffe3a3', emissiveIntensity: 1.6, flatShading: false }), 0.45, 2.22, -3.39);
[[-0.55, 2.3], [-0.3, 1.7], [0.5, 1.65], [-0.6, 1.85]].forEach(([x, y]) =>
  box(0.035, 0.035, 0.02, '#ffffff', x, y, -3.39, { emissive: '#ffffff', emissiveIntensity: 1.2 }));

// "ship it" poster
const poster = new THREE.Mesh(new THREE.PlaneGeometry(1.1, 0.78), new THREE.MeshStandardMaterial({
  map: canvasTex(256, 182, (g, w, h) => {
    g.fillStyle = '#f2efe8'; g.fillRect(0, 0, w, h);
    g.fillStyle = '#14161f'; g.font = 'bold 54px Space Grotesk, Arial, sans-serif'; g.textAlign = 'center';
    g.fillText('ship it', w / 2, h / 2 + 18);
  }), roughness: 0.9
}));
poster.position.set(-2.6, 2.25, -3.49); scene.add(poster);

// clock
const clock = cyl(0.32, 0.32, 0.06, '#f2efe8', 2.7, 2.3, -3.47, 24); clock.rotation.x = Math.PI / 2;
const hourHand = box(0.04, 0.18, 0.02, '#14161f', 2.7, 2.37, -3.42);
const minHand = box(0.03, 0.26, 0.02, '#ffb547', 2.7, 2.3, -3.41);
minHand.geometry.translate(0, 0.13, 0); minHand.position.y = 2.3;
hourHand.geometry.translate(0, 0.09, 0); hourHand.position.y = 2.3;

// code desk
box(2.2, 0.1, 1.0, '#8a6a4f', -2.8, 0.95, -2.9);
[[-1.0, -0.4], [1.0, -0.4], [-1.0, 0.4], [1.0, 0.4]].forEach(([dx, dz]) => box(0.1, 0.9, 0.1, '#6e533d', -2.8 + dx, 0.45, -2.9 + dz));
box(1.0, 0.62, 0.08, '#1c1d24', -2.8, 1.47, -3.22);
box(0.12, 0.3, 0.12, '#3a3e4f', -2.8, 1.12, -3.22);
const codeTex = canvasTex(256, 150, (g, w, h) => {
  g.fillStyle = '#0f1220'; g.fillRect(0, 0, w, h);
  const rows = [[16, 90, '#7cf2c4'], [30, 130, '#6fa8ff'], [30, 70, '#7cf2c4'], [44, 110, '#ffb547'], [16, 60, '#7cf2c4'], [30, 140, '#6fa8ff'], [16, 40, '#ff7a9c']];
  rows.forEach(([x, len, c], i) => { g.fillStyle = c; g.fillRect(x, 14 + i * 19, len, 8); });
});
const codeScreen = new THREE.Mesh(new THREE.PlaneGeometry(0.9, 0.52), new THREE.MeshStandardMaterial({ map: codeTex, emissive: '#ffffff', emissiveMap: codeTex, emissiveIntensity: 0.9 }));
codeScreen.position.set(-2.8, 1.47, -3.175); scene.add(codeScreen);
box(0.7, 0.04, 0.22, '#d8d2c4', -2.8, 1.02, -2.65);
cyl(0.08, 0.08, 0.16, '#ff7a9c', -2.0, 1.08, -2.75, 12);

// bookshelf on the left wall
box(0.5, 1.7, 1.4, '#7a5a42', -4.25, 0.85, -0.6);
const bookColors = ['#6fa8ff', '#ff7a9c', '#ffb547', '#7cf2c4', '#9b8cff', '#e9e4d8', '#ff7a9c', '#6fa8ff'];
[0.45, 0.98, 1.5].forEach((y, r) => {
  let z = -1.2;
  for (let k = 0; k < 6; k++) {
    const w = 0.12 + ((k + r) % 3) * 0.04, hgt = 0.32 + ((k * 2 + r) % 3) * 0.05;
    box(0.32, hgt, w, bookColors[(k + r * 2) % bookColors.length], -3.98, y + hgt / 2 - 0.16, z + w / 2);
    z += w + 0.04;
  }
});

// bean bag and lamp
const bean = add(new THREE.SphereGeometry(0.9, 18, 12), M('#7d6cf0'), 2.8, 0.38, -2.5); bean.scale.set(1, 0.45, 1);
const pillow = add(new THREE.SphereGeometry(0.5, 14, 10), M('#e9e4d8'), 2.8, 0.74, -3.12); pillow.scale.set(1.1, 0.3, 0.6);
cyl(0.04, 0.04, 1.3, '#3a3e4f', 3.95, 0.65, -3.1, 8);
cyl(0.18, 0.3, 0.3, '#ffcf7a', 3.95, 1.4, -3.1, 12, { emissive: '#ffb547', emissiveIntensity: 0.8 });
const lampLight = new THREE.PointLight('#ffb547', 2.5, 4, 2); lampLight.position.set(3.95, 1.3, -3.0); scene.add(lampLight);

// rug
cyl(1.5, 1.5, 0.03, '#e0a34a', 0, 0.015, 0.6, 40);
cyl(1.1, 1.1, 0.035, '#f1c27a', 0, 0.02, 0.6, 40);
cyl(0.6, 0.6, 0.04, '#e0a34a', 0, 0.025, 0.6, 40);

// plant
cyl(0.32, 0.24, 0.5, '#c97b4a', -3.7, 0.25, 2.7, 12);
add(new THREE.IcosahedronGeometry(0.45, 0), M('#4fb286'), -3.7, 0.95, 2.7);
add(new THREE.IcosahedronGeometry(0.3, 0), M('#5cc596'), -3.45, 1.3, 2.6);
add(new THREE.IcosahedronGeometry(0.26, 0), M('#3e9a72'), -3.95, 1.25, 2.85);

// mailbox (events from the Mac arrive here)
box(0.1, 0.9, 0.1, '#6e533d', 3.8, 0.45, 2.7);
box(0.5, 0.32, 0.7, '#6fa8ff', 3.8, 1.04, 2.7);
const roof = cyl(0.25, 0.25, 0.7, '#6fa8ff', 3.8, 1.2, 2.7, 16); roof.rotation.x = Math.PI / 2;
const flag = new THREE.Group(); flag.position.set(4.08, 1.0, 2.85); scene.add(flag);
const flagPole = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.4, 0.04), M('#ff7a9c')); flagPole.position.y = 0.2; flag.add(flagPole);
const flagTip = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.14, 0.2), M('#ff7a9c')); flagTip.position.set(0, 0.33, 0.1); flag.add(flagTip);

// ask spot ring
const askRing = new THREE.Mesh(new THREE.RingGeometry(0.55, 0.62, 48), new THREE.MeshBasicMaterial({ color: '#f2efe8', transparent: true, opacity: 0.55 }));
askRing.rotation.x = -Math.PI / 2; askRing.position.set(0, 0.03, 2.4); askRing.visible = false; scene.add(askRing);

/* ---------- Byte ---------- */
const MOODS = {
  happy: { label: 'Happy', color: '#59f0b5', glow: 6, spot: [0, 0.6], face: 0, energy: 70 },
  focused: { label: 'Focused', color: '#5aa2ff', glow: 7, spot: [-2.8, -1.85], face: Math.PI, energy: 85 },
  sleepy: { label: 'Sleepy', color: '#9b8cff', glow: 1.6, spot: [2.8, -2.45], face: 0, energy: 15 },
  bored: { label: 'Bored', color: '#9aa0ae', glow: 2.2, spot: [-3.0, 1.8], face: Math.atan2(-0.7, 0.9), energy: 35 },
  night: { label: 'Night owl', color: '#ffb547', glow: 6, spot: [0, -2.5], face: Math.PI, energy: 50 },
  celebrating: { label: 'Celebrating', color: '#ff6fa0', glow: 9, spot: [0, 0.6], face: 0, energy: 100 }
};

const botRoot = new THREE.Group(); scene.add(botRoot);
const botYaw = new THREE.Group(); botRoot.add(botYaw);
const botBody = new THREE.Group(); botYaw.add(botBody);
const facingFix = new THREE.Group(); botBody.add(facingFix);

const shadowTex = canvasTex(128, 128, (g) => {
  const gr = g.createRadialGradient(64, 64, 4, 64, 64, 62);
  gr.addColorStop(0, 'rgba(0,0,0,0.55)'); gr.addColorStop(1, 'rgba(0,0,0,0)');
  g.fillStyle = gr; g.fillRect(0, 0, 128, 128);
});
const shadow = new THREE.Mesh(new THREE.PlaneGeometry(1.3, 1.3), new THREE.MeshBasicMaterial({ map: shadowTex, transparent: true, depthWrite: false }));
shadow.rotation.x = -Math.PI / 2; scene.add(shadow);

const state = {
  pos: new THREE.Vector2(0, 0.6), y: 0, vy: 0, baseY: 0, yaw: 0, yawTarget: 0,
  mood: 'happy', target: null, asking: false, walking: false, ready: false, lay: 0,
  placeFace: null // set by byte.goTo: which way to face on arrival instead of the mood's
};
let head = null, headSetup = null, faceMat = null;
const faceColor = new THREE.Color(MOODS.happy.color);
let faceGlow = MOODS.happy.glow;

const loader = new GLTFLoader();
const buf = botBytes.buffer.slice(botBytes.byteOffset, botBytes.byteOffset + botBytes.byteLength);
loader.parse(buf, '', (gltf) => {
  const model = gltf.scene;
  facingFix.add(model);
  model.updateMatrixWorld(true);
  let bb = new THREE.Box3().setFromObject(model);
  const s = 1.15 / (bb.max.y - bb.min.y);
  model.scale.multiplyScalar(s);
  model.updateMatrixWorld(true);
  bb = new THREE.Box3().setFromObject(model);
  const c = bb.getCenter(new THREE.Vector3());
  model.position.x -= c.x; model.position.z -= c.z; model.position.y -= bb.min.y;
  model.updateMatrixWorld(true);

  let faceMesh = null;
  model.traverse((o) => {
    if (o.isMesh && o.material && o.material.name === 'material_4') {
      faceMat = o.material.clone(); o.material = faceMat; faceMesh = o;
    }
  });
  head = model.getObjectByName('Cube');

  if (faceMesh && head) {
    const fc = new THREE.Box3().setFromObject(faceMesh).getCenter(new THREE.Vector3());
    const hc = new THREE.Box3().setFromObject(head).getCenter(new THREE.Vector3());
    const d = fc.sub(hc);
    facingFix.rotation.y = -Math.atan2(d.x, d.z);
    facingFix.updateMatrixWorld(true);
    const parent = head.parent;
    const pq = parent.getWorldQuaternion(new THREE.Quaternion());
    const ps = parent.getWorldScale(new THREE.Vector3()).x;
    headSetup = { basePos: head.position.clone(), baseQuat: head.quaternion.clone(), pq, pqInv: pq.clone().invert(), ps };
  }
  facingFix.updateMatrixWorld(true);
  const bbBot = new THREE.Box3().setFromObject(model);
  botDims.back = -bbBot.min.z; botDims.h = bbBot.max.y - bbBot.min.y;
  state.ready = true;
  $('loading').style.display = 'none';
  setMood(state.mood, true); // 'happy' unless the shell set a mood before the model loaded
  post({ type: 'ready' });
  if (FPS_PROBE) fetch('/__ready', { cache: 'no-store' }).catch(() => {});
}, (err) => {
  $('loading').textContent = 'Could not load Byte'; console.error(err);
  if (FPS_PROBE) fetch('/__err?msg=' + encodeURIComponent('model load: ' + (err && err.message || err)), { cache: 'no-store' }).catch(() => {});
});

const tmpQ = new THREE.Quaternion(), tmpE = new THREE.Euler(), tmpV = new THREE.Vector3();
function poseHead(lift, pitch, roll) {
  if (!head || !headSetup) return;
  const h = headSetup;
  tmpV.set(0, lift, 0).applyQuaternion(h.pqInv).multiplyScalar(1 / h.ps);
  head.position.copy(h.basePos).add(tmpV);
  tmpQ.setFromEuler(tmpE.set(pitch, 0, roll));
  const local = h.pqInv.clone().multiply(tmpQ).multiply(h.pq);
  head.quaternion.copy(local).multiply(h.baseQuat);
}

/* ---------- particles ---------- */
const zTex = canvasTex(64, 64, (g) => { g.fillStyle = '#b7adff'; g.font = 'bold 52px Arial'; g.textAlign = 'center'; g.fillText('z', 32, 50); });
const zs = [0, 1, 2].map(() => { const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: zTex, transparent: true, depthWrite: false })); sp.scale.set(0.3, 0.3, 0.3); scene.add(sp); return sp; });
const confColors = ['#ff6fa0', '#ffb547', '#59f0b5', '#5aa2ff', '#9b8cff', '#f2efe8'];
const confetti = Array.from({ length: 40 }, (_, i) => {
  const m = new THREE.Mesh(new THREE.PlaneGeometry(0.09, 0.05), new THREE.MeshBasicMaterial({ color: confColors[i % confColors.length], side: THREE.DoubleSide }));
  m.visible = false; scene.add(m);
  return { m, v: new THREE.Vector3(), life: 0 };
});
function respawn(p) {
  p.m.position.set(botRoot.position.x, 1.5 + state.y, botRoot.position.z);
  p.v.set((Math.random() - 0.5) * 3, 2 + Math.random() * 2.5, (Math.random() - 0.5) * 3);
  p.life = 1 + Math.random() * 0.8;
  p.m.rotation.set(Math.random() * 6, Math.random() * 6, 0);
}

/* ---------- moods, ask ---------- */
function setMood(id, instant) {
  state.mood = id;
  state.asking = false; showAsk(false);
  state.placeFace = null;
  const m = MOODS[id];
  state.target = new THREE.Vector2(m.spot[0], m.spot[1]);
  if (instant) { state.pos.copy(state.target); state.target = null; state.yaw = state.yawTarget = m.face; }
  flagUp = id === 'celebrating';
  $('moodLabel').textContent = m.label;
  $('moodDot').style.background = m.color;
  $('energyFill').style.background = m.color;
  $('energyFill').style.width = m.energy + '%';
}
let flagUp = false;

const ANSWERS = [
  [/undo|reset|last commit/i, 'git reset --soft HEAD~1. The commit goes, your changes stay.'],
  [/branch/i, 'git switch -c my-branch. Fresh start, same snacks.'],
  [/stash/i, 'git stash now, git stash pop when you are back.'],
  [/regex|email/i, 'Try ^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$ . Not perfect, but neither am I.'],
  [/who|name|what are you/i, 'I am Byte. I live in this room and I eat keystrokes.'],
  [/rebase/i, 'git rebase -i HEAD~3, then squash what you are not proud of.']
];
let typeTimer = null;
function say(text) {
  const el = $('answer'); clearInterval(typeTimer); el.textContent = '';
  let i = 0;
  typeTimer = setInterval(() => { el.textContent = text.slice(0, ++i); if (i >= text.length) clearInterval(typeTimer); }, 22);
}
function showAsk(on) {
  $('askLayer').hidden = !on;
  $('controlsLayer').hidden = on;
  askRing.visible = on;
}
function startAsk() {
  state.asking = true;
  state.target = new THREE.Vector2(0, 2.4);
  showAsk(true);
  $('youAsked').textContent = '';
  say('Hi! Ask me something. I am small, but I try.');
  setTimeout(() => { try { $('q').focus({ preventScroll: true }); } catch (e) {} }, 50);
}
$('askForm').addEventListener('submit', (e) => {
  e.preventDefault();
  const q = $('q').value.trim(); if (!q) return;
  $('youAsked').textContent = 'You asked: ' + q;
  $('q').value = '';
  // In the app the shell asks the brain and drives thinking/speaking; canned answers stay for plain-browser testing.
  // v1 only: typed questions are a test path until voice lands in v2.
  if (hasNativeHost()) { post({ type: 'ask', text: q }); return; }
  const hit = ANSWERS.find(([re]) => re.test(q));
  say(hit ? hit[1] : 'My real brain is not installed yet, so try asking me about git.');
});
$('askBtn').addEventListener('click', () => { startAsk(); post({ type: 'askTapped' }); });
$('closeAsk').addEventListener('click', () => { state.asking = false; showAsk(false); setMood(endTurnByUser()); });
// (the prototype's mood pills and Reset button lived outside the screen; moods now come from window.byte.setMood)

/* ---------- window.byte bridge (native shell <-> world) ---------- */
// App -> world: window.byte.* (see docs/TECHNICAL.md, "Native app to 3D world bridge").
// World -> app: webkit.messageHandlers.byte.postMessage({type: 'ready' | 'askTapped' | 'askClosed'}),
//               plus {type: 'ask', text} for typed questions (v1 test path, removed when voice lands).
// Voice states reuse only the existing face glow, head poses and question bubble.
const VOICE_STATES = ['idle', 'listening', 'thinking', 'speaking'];
const ASK_SPOT = [0, 2.4];
const CELEBRATE_MS = 10000;
const voice = {
  state: 'idle',
  level: 0,         // last value from setLevel, 0..1
  shown: 0,         // smoothed level used for the glow
  pulse: 0,         // spike on each new spoken word, decays to 0
  words: 0,         // word count of the last say() text
  pendingMood: null, // mood requested mid-turn, applied when the turn ends
  lastSayAt: -Infinity // performance.now() of the last say(), to tell when the answer stops streaming
};
const celebration = { timer: null, returnTo: 'happy' };

function nativeHandler() {
  return (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.byte) || null;
}
function hasNativeHost() { return nativeHandler() !== null; }
function post(msg) {
  try {
    const h = nativeHandler();
    if (h) h.postMessage(msg); // no-op in a plain browser
  } catch (e) { console.error('byte bridge: postMessage failed', e); }
}
const inVoiceTurn = () => voice.state !== 'idle';
const currentMood = () => voice.pendingMood || state.mood;
const isMood = (id) => typeof id === 'string' && Object.prototype.hasOwnProperty.call(MOODS, id);

// Walk to a mood's spot, unless a voice turn is holding Byte at the ask spot.
function applyMood(id) {
  if (inVoiceTurn()) { voice.pendingMood = id; return; }
  setMood(id);
}
// The user closed the bubble or steered away mid-turn: drop the turn, tell the shell, return the mood to show.
function endTurnByUser() {
  const id = currentMood();
  voice.state = 'idle'; voice.pendingMood = null; voice.level = 0;
  post({ type: 'askClosed' });
  return id;
}
function setAnswerText(text) { clearInterval(typeTimer); $('answer').textContent = text; }

function bridgeSetMood(id) {
  if (!isMood(id)) { console.warn('byte.setMood: unknown mood', id); return false; }
  clearTimeout(celebration.timer); celebration.timer = null; // an explicit mood ends any celebration
  applyMood(id);
  return true;
}

function bridgeSetVoiceState(s) {
  if (!VOICE_STATES.includes(s)) { console.warn('byte.setVoiceState: unknown state', s); return false; }
  const prev = voice.state;
  voice.state = s;
  if (s === 'idle') {
    voice.level = 0;
    if (prev !== 'idle') { const id = currentMood(); voice.pendingMood = null; setMood(id); } // hides the bubble, walks home
    return true;
  }
  if (!state.asking) { // entering a turn: sit up, walk to the ask spot, face the camera, show the bubble
    state.asking = true;
    state.target = new THREE.Vector2(ASK_SPOT[0], ASK_SPOT[1]);
    showAsk(true);
  }
  if (s === 'listening') { $('youAsked').textContent = ''; setAnswerText('Listening...'); }
  if (s === 'speaking' && prev !== 'speaking') { voice.words = 0; setAnswerText(''); }
  return true;
}

// "text so far": replaces the bubble text; each new word pulses the glow while speaking.
function bridgeSay(text) {
  voice.lastSayAt = performance.now();
  const s = text == null ? '' : String(text);
  setAnswerText(s);
  const n = s.trim() ? s.trim().split(/\s+/).length : 0;
  if (voice.state === 'speaking' && n > voice.words) voice.pulse = 1;
  voice.words = n;
  return true;
}

function bridgeSetLevel(x) {
  const v = Number(x);
  voice.level = Number.isFinite(v) ? THREE.MathUtils.clamp(v, 0, 1) : 0;
  return true;
}

// Push event: celebrate (raises the mailbox flag) for 10 s, then go back to the previous mood.
function bridgeCelebrate() {
  const before = currentMood();
  if (before !== 'celebrating') celebration.returnTo = before; // a second push extends, keeps the original mood
  applyMood('celebrating');
  clearTimeout(celebration.timer);
  celebration.timer = setTimeout(() => {
    celebration.timer = null;
    if (currentMood() === 'celebrating') applyMood(celebration.returnTo);
  }, CELEBRATE_MS);
  return true;
}

// Typed commands (app/Sources/Commands.swift). Spots are in front of each object, clear of its collision shape;
// face is the yaw that looks at the object (same convention as MOODS[].face).
const PLACES = {
  desk: { spot: [-2.8, -1.85], face: Math.PI },               // the Focused spot
  beanBag: { spot: [2.8, -2.45], face: 0 },                   // the Sleepy spot (standing, not lying down)
  plant: { spot: [-3.0, 1.8], face: Math.atan2(-0.7, 0.9) },  // the Bored spot
  window: { spot: [0, -2.5], face: Math.PI },                 // the Night owl spot
  bookshelf: { spot: [-3.3, -0.6], face: -Math.PI / 2 },
  mailbox: { spot: [3.0, 2.0], face: Math.atan2(0.8, 0.7) },
  rug: { spot: [0, 0.6], face: 0 }                            // the Happy spot
};
// Walk to a place and stay there until the next mood, question or D-pad move. The app closes the bubble first.
function bridgeGoTo(id) {
  if (typeof id !== 'string' || !Object.prototype.hasOwnProperty.call(PLACES, id)) { console.warn('byte.goTo: unknown place', id); return false; }
  if (inVoiceTurn()) { console.warn('byte.goTo: ignored during a voice turn'); return false; }
  if (state.mood === 'celebrating') { // walking off ends the party, the same as an explicit mood
    clearTimeout(celebration.timer); celebration.timer = null;
    setMood(celebration.returnTo);
  }
  const p = PLACES[id];
  state.target = new THREE.Vector2(p.spot[0], p.spot[1]);
  state.placeFace = p.face;
  return true;
}
function bridgeJump() { jump(); return true; } // the Jump button's jump: only from the ground

window.byte = Object.freeze({
  setMood: bridgeSetMood,
  setVoiceState: bridgeSetVoiceState,
  say: bridgeSay,
  setLevel: bridgeSetLevel,
  celebrate: bridgeCelebrate,
  goTo: bridgeGoTo,
  jump: bridgeJump
});

/* ---------- input ---------- */
const held = { left: false, right: false, back: false, fwd: false };
const DIRS = { left: [-1, 0], right: [1, 0], back: [0, -1], fwd: [0, 1] };
document.querySelectorAll('[data-dir]').forEach((b) => {
  const d = b.dataset.dir;
  const on = (e) => { e.preventDefault(); held[d] = true; b.setPointerCapture && b.setPointerCapture(e.pointerId); };
  const off = () => { held[d] = false; };
  b.addEventListener('pointerdown', on);
  b.addEventListener('pointerup', off); b.addEventListener('pointercancel', off); b.addEventListener('lostpointercapture', off);
  b.addEventListener('click', (e) => { if (e.detail === 0) { const [dx, dz] = DIRS[d]; state.target = new THREE.Vector2(state.pos.x + dx, state.pos.y + dz); } });
});
function jump() { if (state.y <= 0.001 && state.vy === 0) state.vy = 4.4; }
$('jumpBtn').addEventListener('click', jump);
const KEYMAP = { ArrowLeft: 'left', a: 'left', A: 'left', ArrowRight: 'right', d: 'right', D: 'right', ArrowUp: 'back', w: 'back', W: 'back', ArrowDown: 'fwd', s: 'fwd', S: 'fwd' };
window.addEventListener('keydown', (e) => {
  if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA')) return;
  if (KEYMAP[e.key]) { held[KEYMAP[e.key]] = true; e.preventDefault(); }
  if (e.key === ' ') { jump(); e.preventDefault(); }
});
window.addEventListener('keyup', (e) => { if (KEYMAP[e.key]) held[KEYMAP[e.key]] = false; });
window.addEventListener('blur', () => { Object.keys(held).forEach((k) => (held[k] = false)); });

/* ---------- axis gizmo ---------- */
const gz = { x: [$('gx'), $('gxl')], y: [$('gy'), $('gyl')], z: [$('gz'), $('gzl')] };
const axes = { x: new THREE.Vector3(1, 0, 0), y: new THREE.Vector3(0, 1, 0), z: new THREE.Vector3(0, 0, 1) };
function updateGizmo() {
  const inv = camera.matrixWorldInverse;
  for (const k of ['x', 'y', 'z']) {
    const v = axes[k].clone().transformDirection(inv);
    const ex = 22 + v.x * 16, ey = 22 - v.y * 16;
    gz[k][0].setAttribute('x2', ex.toFixed(1)); gz[k][0].setAttribute('y2', ey.toFixed(1));
    gz[k][1].setAttribute('x', (22 + v.x * 21 - 3).toFixed(1)); gz[k][1].setAttribute('y', (22 - v.y * 21 + 3).toFixed(1));
  }
}
const fmt = (v) => (v > 0.05 ? '+' : v < -0.05 ? '−' : '') + Math.abs(v).toFixed(1);

/* ---------- collisions ---------- */
// Byte is a circle of radius BOT_R on the floor; furniture is boxes and circles on the floor plan (x, z)
const BOT_R = 0.35;
const BOXES = [
  { x0: -3.9, x1: -1.7, z0: -3.4, z1: -2.4 },  // code desk
  { x0: -4.5, x1: -3.8, z0: -1.3, z1: 0.1 },   // bookshelf
  { x0: 3.55, x1: 4.05, z0: 2.35, z1: 3.05 }   // mailbox
];
const CIRCLES = [
  { x: -3.7, z: 2.7, r: 0.45 },  // plant
  { x: 3.95, z: -3.1, r: 0.3 }   // lamp
];
const stuck = { best: Infinity, time: 0 };
const botDims = { back: 0.3, h: 1.15 };
function collide(p) {
  for (const b of BOXES) {
    const x0 = b.x0 - BOT_R, x1 = b.x1 + BOT_R, z0 = b.z0 - BOT_R, z1 = b.z1 + BOT_R;
    if (p.x > x0 && p.x < x1 && p.y > z0 && p.y < z1) {
      const pushL = p.x - x0, pushR = x1 - p.x, pushB = p.y - z0, pushF = z1 - p.y;
      const min = Math.min(pushL, pushR, pushB, pushF);
      if (min === pushL) p.x = x0; else if (min === pushR) p.x = x1; else if (min === pushB) p.y = z0; else p.y = z1;
    }
  }
  for (const c of CIRCLES) {
    const dx = p.x - c.x, dz = p.y - c.z, d = Math.hypot(dx, dz), r = c.r + BOT_R;
    if (d < r) {
      if (d < 1e-4) { p.x = c.x + r; continue; }
      p.x = c.x + dx / d * r; p.y = c.z + dz / d * r;
    }
  }
}

/* ---------- fps probe (testing only: add ?fps to the URL) ---------- */
// Draws nothing. Every 5 s it requests /__fps?avg=..&worst_ms=..; the numbers show up in the
// dev server's access log (as a 404), so the frame rate can be read without Web Inspector.
const FPS_PROBE = /[?&]fps(&|=|$)/.test(location.search);
const FPS_WINDOW_MS = 5000;
const fpsProbe = { frames: 0, start: 0, prev: 0, worst: 0 };
function fpsTick(now) {
  const p = fpsProbe;
  if (!p.start) { p.start = p.prev = now; fetch('/__firstframe', { cache: 'no-store' }).catch(() => {}); return; }
  p.frames++; p.worst = Math.max(p.worst, now - p.prev); p.prev = now;
  if (now - p.start < FPS_WINDOW_MS) return;
  const q = 'avg=' + (p.frames * 1000 / (now - p.start)).toFixed(1) + '&worst_ms=' + p.worst.toFixed(0) +
    '&canvas=' + canvas.width + 'x' + canvas.height + '&mood=' + state.mood;
  fetch('/__fps?' + q, { cache: 'no-store' }).catch(() => {});
  p.frames = 0; p.start = now; p.worst = 0;
}

/* ---------- loop ---------- */
const angDiff = (a, b) => Math.atan2(Math.sin(b - a), Math.cos(b - a));
// Which way Byte faces when it stops: the camera while asking, else a goTo place, else its mood spot's direction.
const restYaw = (m) => (state.asking ? 0 : state.placeFace !== null ? state.placeFace : m.face);
const SPEED = 2.4;
// While the brain works, draw at BUSY_FPS so llama-server gets the CPU (decision 2026-11-16, 3A: the A10 runs two
// fast cores, and 60 fps rendering cut generation from ~9 to ~1 token/s). Busy = Thinking, or Speaking while
// text is still arriving (say() within BUSY_TEXT_MS). Nothing else changes: same scene, fewer frames.
const BUSY_FPS = 15, BUSY_TEXT_MS = 1500, FRAME_SLACK_MS = 2;
const brainBusy = (now) => voice.state === 'thinking' || (voice.state === 'speaking' && now - voice.lastSayAt < BUSY_TEXT_MS);
// Longest step simulated in one frame; covers 15 fps (67 ms) so motion keeps its speed, caps hitches.
const MAX_DT = 0.1;
let last = performance.now(), t = 0;
function frame(now) {
  if (brainBusy(now) && now - last < 1000 / BUSY_FPS - FRAME_SLACK_MS) { requestAnimationFrame(frame); return; }
  const dt = Math.min(MAX_DT, (now - last) / 1000); last = now; t += dt;
  const m = MOODS[state.mood];

  if (state.ready) {
    let ix = 0, iz = 0;
    for (const k in held) if (held[k]) { ix += DIRS[k][0]; iz += DIRS[k][1]; }
    state.walking = false;
    if (ix || iz) {
      if (state.asking) setMood(endTurnByUser()); // hides the bubble; target is cleared next line
      state.target = null;
      const len = Math.hypot(ix, iz); ix /= len; iz /= len;
      state.pos.x += ix * SPEED * dt; state.pos.y += iz * SPEED * dt;
      state.yawTarget = Math.atan2(ix, iz); state.walking = true;
    } else if (state.target) {
      const dx = state.target.x - state.pos.x, dz = state.target.y - state.pos.y, d = Math.hypot(dx, dz);
      if (d > 0.04) {
        const step = Math.min(d, SPEED * dt);
        state.pos.x += dx / d * step; state.pos.y += dz / d * step;
        state.yawTarget = Math.atan2(dx, dz); state.walking = true;
      } else {
        state.pos.copy(state.target); state.target = null;
        state.yawTarget = restYaw(m);
      }
    }
    state.pos.x = THREE.MathUtils.clamp(state.pos.x, -4.1, 4.1);
    state.pos.y = THREE.MathUtils.clamp(state.pos.y, -3.1, 3.1);
    collide(state.pos);

    // if an auto-walk is blocked and makes no progress, give up instead of pushing forever
    if (state.target) {
      const d = state.pos.distanceTo(state.target);
      if (d < stuck.best - 0.02) { stuck.best = d; stuck.time = 0; }
      else if ((stuck.time += dt) > 1.2) { state.target = null; state.yawTarget = restYaw(m); }
    } else { stuck.best = Infinity; stuck.time = 0; }

    // jump physics; celebrating hops on its own once it arrives
    if (state.mood === 'celebrating' && !state.walking && !state.target && !state.asking && state.y <= 0.001 && state.vy === 0) state.vy = 4.6;
    if (state.vy !== 0 || state.y > 0) {
      state.vy -= 12 * dt; state.y += state.vy * dt;
      if (state.y <= 0) { state.y = 0; state.vy = 0; }
    }
    // the bean bag is a surface: Byte climbs its curve and the bag squishes under it
    const beanR = Math.hypot(state.pos.x - 2.8, state.pos.y + 2.5);
    const onBeanF = beanR < 0.85 ? Math.sqrt(1 - Math.pow(beanR / 0.9, 2)) : 0;
    const squish = onBeanF * 0.06;
    const ground = onBeanF > 0 ? 0.38 + 0.405 * (1 - squish / 0.45) * onBeanF - 0.02 : 0;
    state.baseY += (ground - state.baseY) * Math.min(1, dt * 14);
    bean.scale.y += ((0.45 - squish) - bean.scale.y) * Math.min(1, dt * 8);

    // yaw: spin while celebrating in the air
    if (state.mood === 'celebrating' && state.y > 0.05 && !state.walking) state.yaw += dt * 9;
    else state.yaw += angDiff(state.yaw, state.yawTarget) * Math.min(1, dt * 10);

    botRoot.position.set(state.pos.x, state.baseY + state.y, state.pos.y);
    botYaw.rotation.y = state.yaw;

    // body and head pose by mood
    let bob = 0, pitch = 0, roll = 0, hLift = 0, hPitch = 0, hRoll = 0, sy = 1;
    if (state.walking) {
      bob = Math.abs(Math.sin(t * 11)) * 0.07; pitch = 0.12; roll = Math.sin(t * 11) * 0.05;
    } else if (state.asking) {
      bob = Math.sin(t * 3) * 0.03; hPitch = -0.08; hRoll = Math.sin(t * 1.2) * 0.08;
      if (voice.state === 'thinking') { hRoll = 0.28 + Math.sin(t * 0.9) * 0.03; hPitch = -0.12; } // head tilts to one side
    } else {
      switch (state.mood) {
        case 'happy': bob = (Math.sin(t * 3) + 1) * 0.03; roll = Math.sin(t * 1.6) * 0.06; hLift = Math.sin(t * 3 + 1) * 0.02; break;
        case 'focused': hPitch = 0.22 + Math.sin(t * 7) * 0.03; pitch = 0.05; break;
        case 'sleepy': sy = 1 + Math.sin(t * 1.3) * 0.03; hPitch = 0.42 * (1 - state.lay) + 0.05 * state.lay; hRoll = 0.18 * (1 - state.lay) + 0.3 * state.lay; hLift = -0.04 * (1 - state.lay); break;
        case 'bored': roll = Math.sin(t * 0.8) * 0.08; hRoll = 0.3; hPitch = 0.1; break;
        case 'night': hPitch = -0.35; bob = Math.sin(t * 2) * 0.015; break;
        case 'celebrating': hLift = Math.sin(t * 14) * 0.03; roll = Math.sin(t * 8) * 0.1; break;
      }
    }
    // lying down on the bean bag: on its back, head toward the pillow
    const layT = (state.mood === 'sleepy' && !state.target && !state.walking && !state.asking && state.y <= 0.001 && onBeanF > 0.6) ? 1 : 0;
    state.lay += (layT - state.lay) * Math.min(1, dt * 3);
    const L = state.lay;
    botBody.position.set(0, bob * (1 - L) + L * (botDims.back - 0.05), L * botDims.h * 0.5);
    botBody.rotation.set(pitch * (1 - L) - L * Math.PI / 2, 0, roll * (1 - L));
    botBody.scale.set(1 / Math.sqrt(sy), sy, 1 / Math.sqrt(sy));
    poseHead(hLift, hPitch, hRoll);

    // face glow follows the mood
    if (faceMat) {
      faceColor.lerp(new THREE.Color(m.color), Math.min(1, dt * 4));
      let g = m.glow;
      if (state.mood === 'sleepy') g = m.glow * (0.6 + 0.4 * Math.sin(t * 1.3));
      if (state.mood === 'celebrating') g = m.glow * (0.75 + 0.25 * Math.sin(t * 12));
      voice.shown += (voice.level - voice.shown) * Math.min(1, dt * 12);
      voice.pulse = Math.max(0, voice.pulse - dt * 4);
      if (state.asking) {
        switch (voice.state) {
          case 'listening': g = m.glow * (0.45 + 0.9 * voice.shown); break;                         // follows your voice level
          case 'thinking': g = m.glow * (0.6 + 0.4 * Math.sin(t * 2)); break;                       // slow pulse
          case 'speaking': g = m.glow * (0.6 + 0.6 * Math.max(voice.pulse, voice.shown)); break;    // pulse per word
        }
      }
      faceGlow += (g - faceGlow) * Math.min(1, dt * 5);
      faceMat.emissive.copy(faceColor);
      faceMat.color.copy(faceColor);
      faceMat.emissiveIntensity = faceGlow;
    }

    // shadow
    shadow.position.set(state.pos.x, state.baseY + 0.02, state.pos.y);
    const k = 1 / (1 + state.y * 1.2);
    shadow.scale.set(k, k, k); shadow.material.opacity = 0.35 + 0.65 * k;

    // particles
    const sleeping = state.mood === 'sleepy' && !state.walking && !state.target;
    zs.forEach((sp, i) => {
      sp.visible = sleeping;
      if (!sleeping) return;
      const ph = (t * 0.33 + i / 3) % 1;
      sp.position.set(state.pos.x + 0.35 + ph * 0.45, state.baseY + 1.25 - state.lay * 0.55 + ph * 0.9, state.pos.y);
      sp.material.opacity = Math.sin(ph * Math.PI);
      const sc = 0.18 + ph * 0.22; sp.scale.set(sc, sc, sc);
    });
    const party = state.mood === 'celebrating' && !state.target && !state.asking;
    confetti.forEach((p) => {
      if (!party) { p.m.visible = false; p.life = 0; return; }
      if (p.life <= 0) respawn(p);
      p.m.visible = true; p.life -= dt;
      p.v.y -= 6 * dt; p.m.position.addScaledVector(p.v, dt);
      p.m.rotation.x += dt * 6; p.m.rotation.y += dt * 4;
      if (p.m.position.y < 0.05) p.life = 0;
    });

    flag.rotation.z += ((flagUp ? 0 : -Math.PI / 2) - flag.rotation.z) * Math.min(1, dt * 5);
  }

  // clock shows real time
  const d = new Date();
  minHand.rotation.z = -(d.getMinutes() / 60) * Math.PI * 2;
  hourHand.rotation.z = -((d.getHours() % 12) / 12 + d.getMinutes() / 720) * Math.PI * 2;

  controls.update();
  renderer.render(scene, camera);
  updateGizmo();
  $('coords').textContent = 'x ' + fmt(state.pos.x) + ' · y ' + fmt(state.baseY + state.y) + ' · z ' + fmt(state.pos.y);
  if (FPS_PROBE) fpsTick(now);
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

/* ---------- fit the 852 x 480 screen to the display ---------- */
// The HUD keeps its 852 x 480 layout and is scaled as one piece (568 x 320 points on the iPod, so s = 2/3).
// The canvas renders at the scaled size's real pixels instead of 852 x 480 x devicePixelRatio:
// same picture, 2.25x fewer pixels on the iPod (1136 x 640 instead of 1704 x 960).
const SCREEN_W = 852, SCREEN_H = 480, MAX_PIXEL_RATIO = 2;
function fit() {
  const vw = window.innerWidth, vh = window.innerHeight;
  if (!vw || !vh) return;
  const s = Math.min(vw / SCREEN_W, vh / SCREEN_H);
  const ox = (vw - SCREEN_W * s) / 2, oy = (vh - SCREEN_H * s) / 2; // centred; no bars at 16:9
  screenEl.style.transform = 'translate(' + ox + 'px,' + oy + 'px) scale(' + s + ')';
  renderer.setPixelRatio(Math.min(MAX_PIXEL_RATIO, (window.devicePixelRatio || 1) * s));
  resize();
}
window.addEventListener('resize', fit);
window.addEventListener('orientationchange', () => setTimeout(fit, 100)); // iOS reports the new size late
fit();
