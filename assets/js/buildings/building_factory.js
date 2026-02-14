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
  submission_terminal: 0xaa8833,
  containment_trap: 0x664488,
  purification_beacon: 0x44aadd,
  defense_turret: 0xcc3333,
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

function createSubmissionTerminal() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.submission_terminal);

  // Pedestal base
  const base = new THREE.Mesh(new THREE.BoxGeometry(s * 1.0, s * 0.5, s * 1.0), mat);
  base.position.y = s * 0.25;
  group.add(base);

  // Upright panel (the terminal screen)
  const panel = new THREE.Mesh(new THREE.BoxGeometry(s * 0.8, s * 0.7, s * 0.15), mat);
  panel.position.set(0, s * 0.85, -s * 0.3);
  group.add(panel);

  // Screen surface (darker inset)
  const screenMat = makeMaterial(0x334422);
  const screen = new THREE.Mesh(new THREE.BoxGeometry(s * 0.6, s * 0.45, s * 0.05), screenMat);
  screen.position.set(0, s * 0.9, -s * 0.2);
  group.add(screen);

  return group;
}

function createContainmentTrap() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.containment_trap);

  // Base ring (torus)
  const ring = new THREE.Mesh(new THREE.TorusGeometry(s * 0.7, s * 0.12, 6, 8), mat);
  ring.position.y = s * 0.15;
  ring.rotation.x = Math.PI / 2;
  group.add(ring);

  // Central pillar
  const pillar = new THREE.Mesh(
    new THREE.CylinderGeometry(s * 0.2, s * 0.3, s * 1.0, 6),
    mat
  );
  pillar.position.y = s * 0.5;
  group.add(pillar);

  // Top crystal (octahedron)
  const crystalMat = makeMaterial(0x9966cc);
  const crystal = new THREE.Mesh(new THREE.OctahedronGeometry(s * 0.3, 0), crystalMat);
  crystal.position.y = s * 1.2;
  group.add(crystal);

  return group;
}

function createPurificationBeacon() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.purification_beacon);

  // Hexagonal base platform
  const base = new THREE.Mesh(new THREE.CylinderGeometry(s * 0.9, s * 1.0, s * 0.3, 6), mat);
  base.position.y = s * 0.15;
  group.add(base);

  // Central pillar (tall, thin)
  const pillar = new THREE.Mesh(new THREE.CylinderGeometry(s * 0.15, s * 0.25, s * 1.4, 6), mat);
  pillar.position.y = s * 0.9;
  group.add(pillar);

  // Top emitter (glowing sphere)
  const emitterMat = new THREE.MeshLambertMaterial({ color: 0x88ddff, emissive: 0x44aadd, emissiveIntensity: 0.5 });
  const emitter = new THREE.Mesh(new THREE.SphereGeometry(s * 0.35, 8, 8), emitterMat);
  emitter.position.y = s * 1.8;
  group.add(emitter);

  // Shield ring (floating torus)
  const ringMat = new THREE.MeshLambertMaterial({ color: 0x66ccee, transparent: true, opacity: 0.6 });
  const ring = new THREE.Mesh(new THREE.TorusGeometry(s * 0.7, s * 0.06, 6, 12), ringMat);
  ring.position.y = s * 1.3;
  ring.rotation.x = Math.PI / 2;
  group.add(ring);

  return group;
}

function createDefenseTurret() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.defense_turret);

  // Base platform
  const base = new THREE.Mesh(new THREE.BoxGeometry(s * 1.2, s * 0.4, s * 1.2), mat);
  base.position.y = s * 0.2;
  group.add(base);

  // Turret body (rotatable dome)
  const dome = new THREE.Mesh(new THREE.SphereGeometry(s * 0.5, 8, 6, 0, Math.PI * 2, 0, Math.PI / 2), mat);
  dome.position.y = s * 0.4;
  group.add(dome);

  // Barrel (pointing forward in +X direction)
  const barrelMat = makeMaterial(0x444444);
  const barrel = new THREE.Mesh(new THREE.CylinderGeometry(s * 0.1, s * 0.1, s * 0.8, 6), barrelMat);
  barrel.rotation.z = -Math.PI / 2;
  barrel.position.set(s * 0.6, s * 0.65, 0);
  group.add(barrel);

  // Muzzle flash indicator (small red sphere at barrel tip)
  const muzzleMat = new THREE.MeshLambertMaterial({ color: 0xff2222, emissive: 0xff0000, emissiveIntensity: 0.3 });
  const muzzle = new THREE.Mesh(new THREE.SphereGeometry(s * 0.12, 6, 6), muzzleMat);
  muzzle.position.set(s * 1.0, s * 0.65, 0);
  group.add(muzzle);

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
  submission_terminal: createSubmissionTerminal,
  containment_trap: createContainmentTrap,
  purification_beacon: createPurificationBeacon,
  defense_turret: createDefenseTurret,
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
