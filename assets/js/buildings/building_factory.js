import * as THREE from "three";

const BUILDING_SCALE = 0.0075;

const COLORS = {
  miner: 0x8b6914,
  conveyor: 0x888888,
  smelter: 0xcc4411,
  assembler: 0x3366aa,
  refinery: 0x2288aa,
  splitter: 0x22aa88,
  merger: 0x8844aa,
};

function makeMaterial(color) {
  return new THREE.MeshLambertMaterial({ color });
}

function createMiner() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.miner);

  // Base cylinder
  const base = new THREE.Mesh(new THREE.CylinderGeometry(s * 0.8, s * 0.9, s * 0.8, 8), mat);
  base.position.y = s * 0.4;
  group.add(base);

  // Cone top (drill)
  const cone = new THREE.Mesh(new THREE.ConeGeometry(s * 0.5, s * 0.7, 8), mat);
  cone.position.y = s * 1.15;
  group.add(cone);

  return group;
}

function createConveyor() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.conveyor);

  // Flat belt
  const belt = new THREE.Mesh(new THREE.BoxGeometry(s * 1.4, s * 0.25, s * 0.8), mat);
  belt.position.y = s * 0.125;
  group.add(belt);

  // Arrow indicator (darker)
  const arrowMat = makeMaterial(0x555555);
  const arrow = new THREE.Mesh(new THREE.ConeGeometry(s * 0.25, s * 0.35, 4), arrowMat);
  arrow.rotation.z = -Math.PI / 2;
  arrow.position.set(s * 0.45, s * 0.35, 0);
  group.add(arrow);

  return group;
}

function createSmelter() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.smelter);

  // Main body
  const body = new THREE.Mesh(new THREE.BoxGeometry(s * 1.2, s * 0.9, s * 1.0), mat);
  body.position.y = s * 0.45;
  group.add(body);

  // Chimney
  const chimney = new THREE.Mesh(new THREE.CylinderGeometry(s * 0.15, s * 0.2, s * 0.7, 6), mat);
  chimney.position.set(s * 0.3, s * 1.25, s * 0.2);
  group.add(chimney);

  return group;
}

function createAssembler() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.assembler);

  // Wide body
  const body = new THREE.Mesh(new THREE.BoxGeometry(s * 1.5, s * 0.7, s * 1.5), mat);
  body.position.y = s * 0.35;
  group.add(body);

  // Top platform
  const top = new THREE.Mesh(new THREE.BoxGeometry(s * 1.0, s * 0.2, s * 1.0), mat);
  top.position.y = s * 0.8;
  group.add(top);

  return group;
}

function createSplitter() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.splitter);

  // Base
  const base = new THREE.Mesh(new THREE.BoxGeometry(s * 1.2, s * 0.4, s * 1.2), mat);
  base.position.y = s * 0.2;
  group.add(base);

  // Left output chute (toward +X = output direction, offset along Z)
  const left = new THREE.Mesh(new THREE.BoxGeometry(s * 0.6, s * 0.3, s * 0.3), mat);
  left.position.set(s * 0.5, s * 0.55, -s * 0.35);
  group.add(left);

  // Right output chute (toward +X = output direction, offset along Z)
  const right = new THREE.Mesh(new THREE.BoxGeometry(s * 0.6, s * 0.3, s * 0.3), mat);
  right.position.set(s * 0.5, s * 0.55, s * 0.35);
  group.add(right);

  return group;
}

function createMerger() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.merger);

  // Base
  const base = new THREE.Mesh(new THREE.BoxGeometry(s * 1.2, s * 0.4, s * 1.2), mat);
  base.position.y = s * 0.2;
  group.add(base);

  // Single output chute (toward +X = output direction)
  const output = new THREE.Mesh(new THREE.BoxGeometry(s * 0.6, s * 0.3, s * 0.4), mat);
  output.position.set(s * 0.5, s * 0.55, 0);
  group.add(output);

  return group;
}

function createRefinery() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.refinery);

  // Main tank (cylinder)
  const tank = new THREE.Mesh(new THREE.CylinderGeometry(s * 0.6, s * 0.6, s * 1.0, 8), mat);
  tank.position.y = s * 0.5;
  group.add(tank);

  // Secondary tank (smaller, offset)
  const tank2 = new THREE.Mesh(new THREE.CylinderGeometry(s * 0.35, s * 0.35, s * 0.7, 8), mat);
  tank2.position.set(-s * 0.5, s * 0.35, s * 0.3);
  group.add(tank2);

  // Pipe connecting tanks
  const pipeMat = makeMaterial(0x555555);
  const pipe = new THREE.Mesh(new THREE.CylinderGeometry(s * 0.08, s * 0.08, s * 0.6, 6), pipeMat);
  pipe.rotation.z = Math.PI / 2;
  pipe.position.set(-s * 0.2, s * 0.8, s * 0.15);
  group.add(pipe);

  return group;
}

const BUILDERS = {
  miner: createMiner,
  conveyor: createConveyor,
  smelter: createSmelter,
  assembler: createAssembler,
  refinery: createRefinery,
  splitter: createSplitter,
  merger: createMerger,
};

/**
 * Create a Three.js Group representing the given building type.
 * The mesh is oriented with Y-axis as "up" (surface normal direction).
 */
export function createBuildingMesh(type) {
  const builder = BUILDERS[type];
  if (!builder) {
    console.warn(`Unknown building type: ${type}`);
    return new THREE.Group();
  }
  return builder();
}
