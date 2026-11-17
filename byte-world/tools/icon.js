// Renders the app icon: Byte (happy face glow) on the room's background, square, from the world's own model.
// Not part of the shipped world. Build + render: see tools/render-icon.sh.
// Model prep (1.15 units tall, face material 'material_4', facing fix) mirrors main.js's loader; keep them in sync.
import * as THREE from 'three';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import botBytes from '../mini_bot.glb';

const SIZE = 1024;
const ROOM_BG = '#171923';
const HAPPY = { color: '#59f0b5', glow: 6 }; // MOODS.happy in main.js

const canvas = document.getElementById('c');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(1);
renderer.setSize(SIZE, SIZE, false);
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;

const scene = new THREE.Scene();
scene.background = new THREE.Color(ROOM_BG);
scene.add(new THREE.HemisphereLight('#fff1dc', '#5a4a3c', 1.3));
const sun = new THREE.DirectionalLight('#ffe2b8', 1.6);
sun.position.set(4, 8, 5);
scene.add(sun);

const facingFix = new THREE.Group();
scene.add(facingFix);
const buf = botBytes.buffer.slice(botBytes.byteOffset, botBytes.byteOffset + botBytes.byteLength);

new GLTFLoader().parse(buf, '', (gltf) => {
  const model = gltf.scene;
  facingFix.add(model);
  model.updateMatrixWorld(true);
  let bb = new THREE.Box3().setFromObject(model);
  model.scale.multiplyScalar(1.15 / (bb.max.y - bb.min.y));
  model.updateMatrixWorld(true);
  bb = new THREE.Box3().setFromObject(model);
  const c = bb.getCenter(new THREE.Vector3());
  model.position.x -= c.x; model.position.z -= c.z; model.position.y -= bb.min.y;
  model.updateMatrixWorld(true);

  let faceMesh = null;
  model.traverse((o) => {
    if (o.isMesh && o.material && o.material.name === 'material_4') {
      o.material = o.material.clone();
      o.material.color.set(HAPPY.color);
      o.material.emissive.set(HAPPY.color);
      o.material.emissiveIntensity = HAPPY.glow;
      faceMesh = o;
    }
  });
  const head = model.getObjectByName('Cube');
  if (faceMesh && head) {
    const fc = new THREE.Box3().setFromObject(faceMesh).getCenter(new THREE.Vector3());
    const hc = new THREE.Box3().setFromObject(head).getCenter(new THREE.Vector3());
    const d = fc.sub(hc);
    facingFix.rotation.y = -Math.atan2(d.x, d.z);
  }
  facingFix.updateMatrixWorld(true);

  // Frame the whole robot, front on, a touch from above, filling ~80% of the square.
  const box = new THREE.Box3().setFromObject(model);
  const size = box.getSize(new THREE.Vector3()), mid = box.getCenter(new THREE.Vector3());
  const fov = 30, fill = 0.8;
  const camera = new THREE.PerspectiveCamera(fov, 1, 0.01, 100);
  const dist = (Math.max(size.x, size.y) / fill / 2) / Math.tan(THREE.MathUtils.degToRad(fov / 2)) + size.z / 2;
  camera.position.set(mid.x, mid.y + dist * 0.18, mid.z + dist);
  camera.lookAt(mid);
  renderer.render(scene, camera);

  fetch('/save', { method: 'POST', body: canvas.toDataURL('image/png') })
    .then((r) => { document.title = r.ok ? 'icon saved' : 'save failed'; });
}, (err) => { document.title = 'load failed: ' + err; });
