import * as THREE from "three";

const BUILDING_SCALE = 0.0075;

const COLORS = {
  miner: 0x8b6914,
  conveyor: 0x888888,
  conveyor_mk2: 0xaaaacc,
  conveyor_mk3: 0xccccee,
  smelter: 0xcc4411,
  assembler: 0x3366aa,
  refinery: 0x2288aa,
  splitter: 0x22aa88,
  merger: 0x8844aa,
  balancer: 0x44bb99,
  storage_container: 0x997744,
  underground_conduit: 0x6655aa,
  submission_terminal: 0xaa8833,
  containment_trap: 0x664488,
  purification_beacon: 0x44aadd,
  defense_turret: 0xcc3333,
  claim_beacon: 0x33aa55,
  trade_terminal: 0xddaa33,
  crossover: 0x77aa77,
  dimensional_stabilizer: 0x3366aa,
  astral_projection_chamber: 0x8866cc,
  gathering_post: 0x66884a,
  drone_bay: 0x445577,
  loader: 0x55aa77,
  unloader: 0x77aa55,
  mixer: 0x8855aa,
};

// Shared material cache — reuse materials across all buildings of the same color
const _materialCache = new Map();
function makeMaterial(color) {
  if (_materialCache.has(color)) return _materialCache.get(color);
  const mat = new THREE.MeshLambertMaterial({ color });
  mat._shared = true;
  _materialCache.set(color, mat);
  return mat;
}

// Shared geometry cache — reuse geometries across all buildings of the same type
const s = BUILDING_SCALE;
const _SHARED_GEOMETRIES_RAW = {
  // Miner
  miner_base: new THREE.CylinderGeometry(s * 0.8, s * 0.9, s * 0.8, 8),
  miner_cone: new THREE.ConeGeometry(s * 0.5, s * 0.7, 8),
  // Conveyor family
  conveyor_belt: new THREE.BoxGeometry(s * 1.4, s * 0.25, s * 0.8),
  conveyor_arrow: new THREE.ConeGeometry(s * 0.25, s * 0.35, 4),
  conveyor_mk2_belt: new THREE.BoxGeometry(s * 1.4, s * 0.3, s * 0.9),
  conveyor_mk2_rail: new THREE.BoxGeometry(s * 1.4, s * 0.15, s * 0.08),
  conveyor_mk2_arrow1: new THREE.ConeGeometry(s * 0.2, s * 0.3, 4),
  conveyor_mk2_arrow2: new THREE.ConeGeometry(s * 0.15, s * 0.2, 4),
  conveyor_mk3_belt: new THREE.BoxGeometry(s * 1.4, s * 0.35, s * 1.0),
  conveyor_mk3_cover: new THREE.BoxGeometry(s * 1.2, s * 0.1, s * 0.8),
  conveyor_mk3_arrow: new THREE.ConeGeometry(s * 0.15, s * 0.2, 4),
  // Smelter
  smelter_body: new THREE.BoxGeometry(s * 1.2, s * 0.9, s * 1.0),
  smelter_chimney: new THREE.CylinderGeometry(s * 0.15, s * 0.2, s * 0.7, 6),
  // Assembler
  assembler_body: new THREE.BoxGeometry(s * 1.5, s * 0.7, s * 1.5),
  assembler_top: new THREE.BoxGeometry(s * 1.0, s * 0.2, s * 1.0),
  // Splitter / Merger / Balancer
  logistics_base: new THREE.BoxGeometry(s * 1.2, s * 0.4, s * 1.2),
  splitter_chute: new THREE.BoxGeometry(s * 0.6, s * 0.3, s * 0.3),
  merger_output: new THREE.BoxGeometry(s * 0.6, s * 0.3, s * 0.4),
  balancer_beam: new THREE.BoxGeometry(s * 1.0, s * 0.08, s * 0.08),
  balancer_pan: new THREE.CylinderGeometry(s * 0.2, s * 0.2, s * 0.06, 6),
  // Refinery
  refinery_tank: new THREE.CylinderGeometry(s * 0.6, s * 0.6, s * 1.0, 8),
  refinery_tank2: new THREE.CylinderGeometry(s * 0.35, s * 0.35, s * 0.7, 8),
  refinery_pipe: new THREE.CylinderGeometry(s * 0.08, s * 0.08, s * 0.6, 6),
  // Storage container
  storage_body: new THREE.BoxGeometry(s * 1.4, s * 1.0, s * 1.2),
  storage_lid: new THREE.BoxGeometry(s * 1.5, s * 0.15, s * 1.3),
  storage_handle: new THREE.BoxGeometry(s * 0.4, s * 0.08, s * 0.08),
  // Submission terminal
  terminal_base: new THREE.BoxGeometry(s * 1.0, s * 0.5, s * 1.0),
  terminal_panel: new THREE.BoxGeometry(s * 0.8, s * 0.7, s * 0.15),
  terminal_screen: new THREE.BoxGeometry(s * 0.6, s * 0.45, s * 0.05),
  // Underground conduit
  conduit_ring: new THREE.TorusGeometry(s * 0.6, s * 0.12, 6, 8),
  conduit_glow: new THREE.SphereGeometry(s * 0.35, 8, 8),
  conduit_arrow: new THREE.ConeGeometry(s * 0.2, s * 0.3, 4),
  // Containment trap
  trap_ring: new THREE.TorusGeometry(s * 0.7, s * 0.12, 6, 8),
  trap_pillar: new THREE.CylinderGeometry(s * 0.2, s * 0.3, s * 1.0, 6),
  trap_crystal: new THREE.OctahedronGeometry(s * 0.3, 0),
  // Purification beacon
  purify_base: new THREE.CylinderGeometry(s * 0.9, s * 1.0, s * 0.3, 6),
  purify_pillar: new THREE.CylinderGeometry(s * 0.15, s * 0.25, s * 1.4, 6),
  purify_emitter: new THREE.SphereGeometry(s * 0.35, 8, 8),
  purify_ring: new THREE.TorusGeometry(s * 0.7, s * 0.06, 6, 12),
  // Defense turret
  turret_base: new THREE.BoxGeometry(s * 1.2, s * 0.4, s * 1.2),
  turret_dome: new THREE.SphereGeometry(s * 0.5, 8, 6, 0, Math.PI * 2, 0, Math.PI / 2),
  turret_barrel: new THREE.CylinderGeometry(s * 0.1, s * 0.1, s * 0.8, 6),
  turret_muzzle: new THREE.SphereGeometry(s * 0.12, 6, 6),
  // Claim beacon
  beacon_base: new THREE.CylinderGeometry(s * 1.0, s * 1.1, s * 0.25, 6),
  beacon_pillar: new THREE.CylinderGeometry(s * 0.2, s * 0.3, s * 1.2, 6),
  beacon_flag: new THREE.OctahedronGeometry(s * 0.35, 0),
  beacon_ring: new THREE.TorusGeometry(s * 0.8, s * 0.05, 6, 12),
  // Trade terminal
  trade_base: new THREE.BoxGeometry(s * 1.2, s * 0.4, s * 1.0),
  trade_slot: new THREE.BoxGeometry(s * 0.3, s * 0.6, s * 0.5),
  trade_bar: new THREE.BoxGeometry(s * 0.4, s * 0.1, s * 0.15),
  // Crossover
  crossover_hBelt: new THREE.BoxGeometry(s * 1.6, s * 0.25, s * 0.5),
  crossover_vBelt: new THREE.BoxGeometry(s * 0.5, s * 0.25, s * 1.6),
  crossover_hub: new THREE.CylinderGeometry(s * 0.3, s * 0.3, s * 0.15, 8),
  // Gathering post
  post_stake: new THREE.CylinderGeometry(s * 0.12, s * 0.15, s * 1.4, 6),
  post_platform: new THREE.CylinderGeometry(s * 0.6, s * 0.7, s * 0.15, 6),
  post_cap: new THREE.ConeGeometry(s * 0.2, s * 0.3, 6),
  post_lure: new THREE.SphereGeometry(s * 0.15, 6, 6),
  // Dimensional stabilizer
  stabilizer_base: new THREE.CylinderGeometry(s * 1.2, s * 1.3, s * 0.4, 6),
  stabilizer_column: new THREE.CylinderGeometry(s * 0.25, s * 0.4, s * 2.0, 8),
  stabilizer_sphere: new THREE.SphereGeometry(s * 0.4, 12, 12),
  // Astral projection chamber
  astral_base: new THREE.CylinderGeometry(s * 1.0, s * 1.1, s * 0.3, 8),
  astral_dome: new THREE.SphereGeometry(s * 0.8, 12, 8, 0, Math.PI * 2, 0, Math.PI / 2),
  astral_pillar: new THREE.CylinderGeometry(s * 0.1, s * 0.15, s * 1.2, 6),
  astral_eye: new THREE.IcosahedronGeometry(s * 0.3, 0),
  // Drone bay
  drone_bay_pad: new THREE.CylinderGeometry(s * 0.9, s * 1.0, s * 0.2, 8),
  drone_bay_mast: new THREE.CylinderGeometry(s * 0.08, s * 0.1, s * 1.4, 6),
  drone_bay_dish: new THREE.SphereGeometry(s * 0.3, 8, 4, 0, Math.PI * 2, 0, Math.PI / 2),
  drone_bay_arm: new THREE.BoxGeometry(s * 0.6, s * 0.06, s * 0.06),
  // Mixer
  mixer_vat: new THREE.CylinderGeometry(s * 0.8, s * 0.7, s * 0.9, 8),
  mixer_funnel: new THREE.CylinderGeometry(s * 0.15, s * 0.25, s * 0.4, 6),
  mixer_blade: new THREE.BoxGeometry(s * 0.6, s * 0.05, s * 0.1),
  // Loader / Unloader arms
  arm_base: new THREE.CylinderGeometry(s * 0.7, s * 0.8, s * 0.3, 6),
  arm_pillar: new THREE.CylinderGeometry(s * 0.12, s * 0.15, s * 1.0, 6),
  arm_boom: new THREE.BoxGeometry(s * 1.2, s * 0.08, s * 0.08),
  arm_claw: new THREE.BoxGeometry(s * 0.15, s * 0.4, s * 0.15),
};
// Mark all shared geometries so they won't be disposed when individual buildings are removed
const SHARED_GEOMETRIES = Object.fromEntries(
  Object.entries(_SHARED_GEOMETRIES_RAW).map(([k, geo]) => { geo._shared = true; return [k, geo]; })
);

function createMiner() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.miner);

  const base = new THREE.Mesh(SHARED_GEOMETRIES.miner_base, mat);
  base.position.y = s * 0.4;
  group.add(base);

  const cone = new THREE.Mesh(SHARED_GEOMETRIES.miner_cone, mat);
  cone.position.y = s * 1.15;
  group.add(cone);

  return group;
}

function createConveyor() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.conveyor);

  const belt = new THREE.Mesh(SHARED_GEOMETRIES.conveyor_belt, mat);
  belt.position.y = s * 0.125;
  group.add(belt);

  const arrowMat = makeMaterial(0x555555);
  const arrow = new THREE.Mesh(SHARED_GEOMETRIES.conveyor_arrow, arrowMat);
  arrow.rotation.z = -Math.PI / 2;
  arrow.position.set(s * 0.45, s * 0.35, 0);
  group.add(arrow);

  return group;
}

function createSmelter() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.smelter);

  const body = new THREE.Mesh(SHARED_GEOMETRIES.smelter_body, mat);
  body.position.y = s * 0.45;
  group.add(body);

  const chimney = new THREE.Mesh(SHARED_GEOMETRIES.smelter_chimney, mat);
  chimney.position.set(s * 0.3, s * 1.25, s * 0.2);
  group.add(chimney);

  return group;
}

function createAssembler() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.assembler);

  const body = new THREE.Mesh(SHARED_GEOMETRIES.assembler_body, mat);
  body.position.y = s * 0.35;
  group.add(body);

  const top = new THREE.Mesh(SHARED_GEOMETRIES.assembler_top, mat);
  top.position.y = s * 0.8;
  group.add(top);

  return group;
}

function createSplitter() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.splitter);

  const base = new THREE.Mesh(SHARED_GEOMETRIES.logistics_base, mat);
  base.position.y = s * 0.2;
  group.add(base);

  const left = new THREE.Mesh(SHARED_GEOMETRIES.splitter_chute, mat);
  left.position.set(s * 0.5, s * 0.55, -s * 0.35);
  group.add(left);

  const right = new THREE.Mesh(SHARED_GEOMETRIES.splitter_chute, mat);
  right.position.set(s * 0.5, s * 0.55, s * 0.35);
  group.add(right);

  return group;
}

function createMerger() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.merger);

  const base = new THREE.Mesh(SHARED_GEOMETRIES.logistics_base, mat);
  base.position.y = s * 0.2;
  group.add(base);

  const output = new THREE.Mesh(SHARED_GEOMETRIES.merger_output, mat);
  output.position.set(s * 0.5, s * 0.55, 0);
  group.add(output);

  return group;
}

function createRefinery() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.refinery);

  const tank = new THREE.Mesh(SHARED_GEOMETRIES.refinery_tank, mat);
  tank.position.y = s * 0.5;
  group.add(tank);

  const tank2 = new THREE.Mesh(SHARED_GEOMETRIES.refinery_tank2, mat);
  tank2.position.set(-s * 0.5, s * 0.35, s * 0.3);
  group.add(tank2);

  const pipeMat = makeMaterial(0x555555);
  const pipe = new THREE.Mesh(SHARED_GEOMETRIES.refinery_pipe, pipeMat);
  pipe.rotation.z = Math.PI / 2;
  pipe.position.set(-s * 0.2, s * 0.8, s * 0.15);
  group.add(pipe);

  return group;
}

function createSubmissionTerminal() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.submission_terminal);

  const base = new THREE.Mesh(SHARED_GEOMETRIES.terminal_base, mat);
  base.position.y = s * 0.25;
  group.add(base);

  const panel = new THREE.Mesh(SHARED_GEOMETRIES.terminal_panel, mat);
  panel.position.set(0, s * 0.85, -s * 0.3);
  group.add(panel);

  const screenMat = makeMaterial(0x334422);
  const screen = new THREE.Mesh(SHARED_GEOMETRIES.terminal_screen, screenMat);
  screen.position.set(0, s * 0.9, -s * 0.2);
  group.add(screen);

  return group;
}

function createContainmentTrap() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.containment_trap);

  const ring = new THREE.Mesh(SHARED_GEOMETRIES.trap_ring, mat);
  ring.position.y = s * 0.15;
  ring.rotation.x = Math.PI / 2;
  group.add(ring);

  const pillar = new THREE.Mesh(SHARED_GEOMETRIES.trap_pillar, mat);
  pillar.position.y = s * 0.5;
  group.add(pillar);

  const crystalMat = makeMaterial(0x9966cc);
  const crystal = new THREE.Mesh(SHARED_GEOMETRIES.trap_crystal, crystalMat);
  crystal.position.y = s * 1.2;
  group.add(crystal);

  return group;
}

function createPurificationBeacon() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.purification_beacon);

  const base = new THREE.Mesh(SHARED_GEOMETRIES.purify_base, mat);
  base.position.y = s * 0.15;
  group.add(base);

  const pillar = new THREE.Mesh(SHARED_GEOMETRIES.purify_pillar, mat);
  pillar.position.y = s * 0.9;
  group.add(pillar);

  const emitterMat = makeMaterial(0x88ddff);
  const emitter = new THREE.Mesh(SHARED_GEOMETRIES.purify_emitter, emitterMat);
  emitter.position.y = s * 1.8;
  group.add(emitter);

  const ringMat = new THREE.MeshLambertMaterial({ color: 0x66ccee, transparent: true, opacity: 0.6 });
  const ring = new THREE.Mesh(SHARED_GEOMETRIES.purify_ring, ringMat);
  ring.position.y = s * 1.3;
  ring.rotation.x = Math.PI / 2;
  group.add(ring);

  return group;
}

function createDefenseTurret() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.defense_turret);

  const base = new THREE.Mesh(SHARED_GEOMETRIES.turret_base, mat);
  base.position.y = s * 0.2;
  group.add(base);

  const dome = new THREE.Mesh(SHARED_GEOMETRIES.turret_dome, mat);
  dome.position.y = s * 0.4;
  group.add(dome);

  const barrelMat = makeMaterial(0x444444);
  const barrel = new THREE.Mesh(SHARED_GEOMETRIES.turret_barrel, barrelMat);
  barrel.rotation.z = -Math.PI / 2;
  barrel.position.set(s * 0.6, s * 0.65, 0);
  group.add(barrel);

  const muzzleMat = makeMaterial(0xff2222);
  const muzzle = new THREE.Mesh(SHARED_GEOMETRIES.turret_muzzle, muzzleMat);
  muzzle.position.set(s * 1.0, s * 0.65, 0);
  group.add(muzzle);

  return group;
}

function createClaimBeacon() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.claim_beacon);

  const base = new THREE.Mesh(SHARED_GEOMETRIES.beacon_base, mat);
  base.position.y = s * 0.125;
  group.add(base);

  const pillar = new THREE.Mesh(SHARED_GEOMETRIES.beacon_pillar, mat);
  pillar.position.y = s * 0.85;
  group.add(pillar);

  const flagMat = makeMaterial(0x55dd77);
  const flag = new THREE.Mesh(SHARED_GEOMETRIES.beacon_flag, flagMat);
  flag.position.y = s * 1.7;
  flag.rotation.y = Math.PI / 4;
  group.add(flag);

  const ringMat = new THREE.MeshLambertMaterial({ color: 0x44cc66, transparent: true, opacity: 0.4 });
  const ring = new THREE.Mesh(SHARED_GEOMETRIES.beacon_ring, ringMat);
  ring.position.y = s * 1.2;
  ring.rotation.x = Math.PI / 2;
  group.add(ring);

  return group;
}

function createTradeTerminal() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.trade_terminal);

  const base = new THREE.Mesh(SHARED_GEOMETRIES.trade_base, mat);
  base.position.y = s * 0.2;
  group.add(base);

  const slotMat = makeMaterial(0xbb8822);
  const slotL = new THREE.Mesh(SHARED_GEOMETRIES.trade_slot, slotMat);
  slotL.position.set(-s * 0.35, s * 0.7, 0);
  group.add(slotL);

  const slotR = new THREE.Mesh(SHARED_GEOMETRIES.trade_slot, slotMat);
  slotR.position.set(s * 0.35, s * 0.7, 0);
  group.add(slotR);

  const arrowMat = makeMaterial(0xffcc44);
  const bar = new THREE.Mesh(SHARED_GEOMETRIES.trade_bar, arrowMat);
  bar.position.set(0, s * 0.7, 0);
  group.add(bar);

  return group;
}

function createConveyorMk2() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.conveyor_mk2);

  const belt = new THREE.Mesh(SHARED_GEOMETRIES.conveyor_mk2_belt, mat);
  belt.position.y = s * 0.15;
  group.add(belt);

  const railMat = makeMaterial(0x8888aa);
  const railL = new THREE.Mesh(SHARED_GEOMETRIES.conveyor_mk2_rail, railMat);
  railL.position.set(0, s * 0.35, -s * 0.45);
  group.add(railL);
  const railR = new THREE.Mesh(SHARED_GEOMETRIES.conveyor_mk2_rail, railMat);
  railR.position.set(0, s * 0.35, s * 0.45);
  group.add(railR);

  const arrowMat = makeMaterial(0x6666aa);
  const arrow1 = new THREE.Mesh(SHARED_GEOMETRIES.conveyor_mk2_arrow1, arrowMat);
  arrow1.rotation.z = -Math.PI / 2;
  arrow1.position.set(s * 0.3, s * 0.4, 0);
  group.add(arrow1);
  const arrow2 = new THREE.Mesh(SHARED_GEOMETRIES.conveyor_mk2_arrow2, arrowMat);
  arrow2.rotation.z = -Math.PI / 2;
  arrow2.position.set(s * 0.0, s * 0.4, 0);
  group.add(arrow2);

  return group;
}

function createConveyorMk3() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.conveyor_mk3);

  const belt = new THREE.Mesh(SHARED_GEOMETRIES.conveyor_mk3_belt, mat);
  belt.position.y = s * 0.175;
  group.add(belt);

  const coverMat = new THREE.MeshLambertMaterial({ color: 0xbbbbdd, transparent: true, opacity: 0.6 });
  const cover = new THREE.Mesh(SHARED_GEOMETRIES.conveyor_mk3_cover, coverMat);
  cover.position.y = s * 0.4;
  group.add(cover);

  const arrowMat = makeMaterial(0x8888cc);
  for (let i = 0; i < 3; i++) {
    const arrow = new THREE.Mesh(SHARED_GEOMETRIES.conveyor_mk3_arrow, arrowMat);
    arrow.rotation.z = -Math.PI / 2;
    arrow.position.set(s * (0.35 - i * 0.25), s * 0.5, 0);
    group.add(arrow);
  }

  return group;
}

function createBalancer() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.balancer);

  const base = new THREE.Mesh(SHARED_GEOMETRIES.logistics_base, mat);
  base.position.y = s * 0.2;
  group.add(base);

  const scaleMat = makeMaterial(0x33aa77);
  const beam = new THREE.Mesh(SHARED_GEOMETRIES.balancer_beam, scaleMat);
  beam.position.set(0, s * 0.65, 0);
  group.add(beam);

  const panL = new THREE.Mesh(SHARED_GEOMETRIES.balancer_pan, scaleMat);
  panL.position.set(-s * 0.4, s * 0.55, 0);
  group.add(panL);

  const panR = new THREE.Mesh(SHARED_GEOMETRIES.balancer_pan, scaleMat);
  panR.position.set(s * 0.4, s * 0.55, 0);
  group.add(panR);

  return group;
}

function createStorageContainer() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.storage_container);

  const body = new THREE.Mesh(SHARED_GEOMETRIES.storage_body, mat);
  body.position.y = s * 0.5;
  group.add(body);

  const lidMat = makeMaterial(0xaa8855);
  const lid = new THREE.Mesh(SHARED_GEOMETRIES.storage_lid, lidMat);
  lid.position.y = s * 1.075;
  group.add(lid);

  const handleMat = makeMaterial(0x555555);
  const handle = new THREE.Mesh(SHARED_GEOMETRIES.storage_handle, handleMat);
  handle.position.set(0, s * 1.2, 0);
  group.add(handle);

  return group;
}

function createUndergroundConduit() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.underground_conduit);

  const ring = new THREE.Mesh(SHARED_GEOMETRIES.conduit_ring, mat);
  ring.position.y = s * 0.3;
  ring.rotation.x = Math.PI / 2;
  group.add(ring);

  const glowMat = makeMaterial(0x9977dd);
  const glow = new THREE.Mesh(SHARED_GEOMETRIES.conduit_glow, glowMat);
  glow.position.y = s * 0.3;
  group.add(glow);

  const arrowMat = makeMaterial(0x4433aa);
  const arrow = new THREE.Mesh(SHARED_GEOMETRIES.conduit_arrow, arrowMat);
  arrow.rotation.z = -Math.PI / 2;
  arrow.position.set(s * 0.4, s * 0.6, 0);
  group.add(arrow);

  return group;
}

function createCrossover() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.crossover);

  const hBelt = new THREE.Mesh(SHARED_GEOMETRIES.crossover_hBelt, mat);
  hBelt.position.y = s * 0.125;
  group.add(hBelt);

  const vBelt = new THREE.Mesh(SHARED_GEOMETRIES.crossover_vBelt, mat);
  vBelt.position.y = s * 0.125;
  group.add(vBelt);

  const hubMat = makeMaterial(0x559955);
  const hub = new THREE.Mesh(SHARED_GEOMETRIES.crossover_hub, hubMat);
  hub.position.y = s * 0.325;
  group.add(hub);

  return group;
}

function createDimensionalStabilizer() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;

  const baseMat = makeMaterial(0x224466);
  const base = new THREE.Mesh(SHARED_GEOMETRIES.stabilizer_base, baseMat);
  base.position.y = s * 0.2;
  group.add(base);

  const colMat = makeMaterial(0x3366aa);
  const column = new THREE.Mesh(SHARED_GEOMETRIES.stabilizer_column, colMat);
  column.position.y = s * 1.2;
  group.add(column);

  const ringMat = new THREE.MeshLambertMaterial({ color: 0x66aaff, emissive: 0x2244aa, emissiveIntensity: 0.4, transparent: true, opacity: 0.7 });
  const ringGeos = [
    new THREE.TorusGeometry(s * 0.6, s * 0.05, 6, 12),
    new THREE.TorusGeometry(s * 0.75, s * 0.05, 6, 12),
    new THREE.TorusGeometry(s * 0.9, s * 0.05, 6, 12),
  ];
  for (let i = 0; i < 3; i++) {
    const ring = new THREE.Mesh(ringGeos[i], ringMat);
    ring.position.y = s * (1.0 + i * 0.5);
    ring.rotation.x = Math.PI / 2;
    group.add(ring);
  }

  const sphereMat = makeMaterial(0xaaddff);
  const sphere = new THREE.Mesh(SHARED_GEOMETRIES.stabilizer_sphere, sphereMat);
  sphere.position.y = s * 2.5;
  group.add(sphere);

  return group;
}

function createAstralProjectionChamber() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;

  const baseMat = makeMaterial(0x332255);
  const base = new THREE.Mesh(SHARED_GEOMETRIES.astral_base, baseMat);
  base.position.y = s * 0.15;
  group.add(base);

  const domeMat = new THREE.MeshLambertMaterial({ color: 0x8866cc, transparent: true, opacity: 0.35 });
  const dome = new THREE.Mesh(SHARED_GEOMETRIES.astral_dome, domeMat);
  dome.position.y = s * 0.3;
  group.add(dome);

  const pillarMat = makeMaterial(0xaa88ff);
  const pillar = new THREE.Mesh(SHARED_GEOMETRIES.astral_pillar, pillarMat);
  pillar.position.y = s * 0.9;
  group.add(pillar);

  const eyeMat = makeMaterial(0xcc99ff);
  const eye = new THREE.Mesh(SHARED_GEOMETRIES.astral_eye, eyeMat);
  eye.position.y = s * 1.7;
  group.add(eye);

  return group;
}

function createGatheringPost() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.gathering_post);

  const platform = new THREE.Mesh(SHARED_GEOMETRIES.post_platform, mat);
  platform.position.y = s * 0.075;
  group.add(platform);

  const stake = new THREE.Mesh(SHARED_GEOMETRIES.post_stake, mat);
  stake.position.y = s * 0.85;
  group.add(stake);

  const cap = new THREE.Mesh(SHARED_GEOMETRIES.post_cap, mat);
  cap.position.y = s * 1.7;
  group.add(cap);

  const lureMat = makeMaterial(0xaadd66);
  const lure = new THREE.Mesh(SHARED_GEOMETRIES.post_lure, lureMat);
  lure.position.y = s * 2.0;
  group.add(lure);

  return group;
}

function createDroneBay() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.drone_bay);

  // Landing pad base
  const pad = new THREE.Mesh(SHARED_GEOMETRIES.drone_bay_pad, mat);
  pad.position.y = s * 0.1;
  group.add(pad);

  // Central antenna mast
  const mast = new THREE.Mesh(SHARED_GEOMETRIES.drone_bay_mast, makeMaterial(0x667799));
  mast.position.y = s * 0.9;
  group.add(mast);

  // Dish on top of mast
  const dish = new THREE.Mesh(SHARED_GEOMETRIES.drone_bay_dish, makeMaterial(0x88aacc));
  dish.position.y = s * 1.6;
  group.add(dish);

  // Cross arms on pad
  const armMat = makeMaterial(0x556688);
  const arm1 = new THREE.Mesh(SHARED_GEOMETRIES.drone_bay_arm, armMat);
  arm1.position.y = s * 0.23;
  group.add(arm1);
  const arm2 = new THREE.Mesh(SHARED_GEOMETRIES.drone_bay_arm, armMat);
  arm2.position.y = s * 0.23;
  arm2.rotation.y = Math.PI / 2;
  group.add(arm2);

  return group;
}

function createLoader() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.loader);

  // Hexagonal base platform
  const base = new THREE.Mesh(SHARED_GEOMETRIES.arm_base, mat);
  base.position.y = s * 0.15;
  group.add(base);

  // Vertical pillar
  const pillar = new THREE.Mesh(SHARED_GEOMETRIES.arm_pillar, mat);
  pillar.position.y = s * 0.8;
  group.add(pillar);

  // Horizontal boom (points forward — toward destination)
  const boomMat = makeMaterial(0x448866);
  const boom = new THREE.Mesh(SHARED_GEOMETRIES.arm_boom, boomMat);
  boom.position.set(s * 0.5, s * 1.3, 0);
  group.add(boom);

  // Claw/gripper at end of boom
  const clawMat = makeMaterial(0x336655);
  const claw = new THREE.Mesh(SHARED_GEOMETRIES.arm_claw, clawMat);
  claw.position.set(s * 1.1, s * 1.1, 0);
  group.add(claw);

  return group;
}

function createUnloader() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.unloader);

  // Hexagonal base platform
  const base = new THREE.Mesh(SHARED_GEOMETRIES.arm_base, mat);
  base.position.y = s * 0.15;
  group.add(base);

  // Vertical pillar
  const pillar = new THREE.Mesh(SHARED_GEOMETRIES.arm_pillar, mat);
  pillar.position.y = s * 0.8;
  group.add(pillar);

  // Horizontal boom (points backward — toward source)
  const boomMat = makeMaterial(0x668844);
  const boom = new THREE.Mesh(SHARED_GEOMETRIES.arm_boom, boomMat);
  boom.position.set(-s * 0.5, s * 1.3, 0);
  group.add(boom);

  // Claw/gripper at end of boom
  const clawMat = makeMaterial(0x556633);
  const claw = new THREE.Mesh(SHARED_GEOMETRIES.arm_claw, clawMat);
  claw.position.set(-s * 1.1, s * 1.1, 0);
  group.add(claw);

  return group;
}

function createMixer() {
  const group = new THREE.Group();
  const s = BUILDING_SCALE;
  const mat = makeMaterial(COLORS.mixer);

  // Main vat body
  const vat = new THREE.Mesh(SHARED_GEOMETRIES.mixer_vat, mat);
  vat.position.y = s * 0.45;
  group.add(vat);

  // Two input funnels on top
  const funnelMat = makeMaterial(0x666688);
  const funnel1 = new THREE.Mesh(SHARED_GEOMETRIES.mixer_funnel, funnelMat);
  funnel1.position.set(-s * 0.35, s * 1.1, 0);
  group.add(funnel1);

  const funnel2 = new THREE.Mesh(SHARED_GEOMETRIES.mixer_funnel, funnelMat);
  funnel2.position.set(s * 0.35, s * 1.1, 0);
  group.add(funnel2);

  // Mixing blade (visible through top)
  const bladeMat = makeMaterial(0x999999);
  const blade = new THREE.Mesh(SHARED_GEOMETRIES.mixer_blade, bladeMat);
  blade.position.y = s * 0.7;
  group.add(blade);

  return group;
}

const BUILDERS = {
  miner: createMiner,
  conveyor: createConveyor,
  conveyor_mk2: createConveyorMk2,
  conveyor_mk3: createConveyorMk3,
  smelter: createSmelter,
  assembler: createAssembler,
  refinery: createRefinery,
  splitter: createSplitter,
  merger: createMerger,
  balancer: createBalancer,
  storage_container: createStorageContainer,
  underground_conduit: createUndergroundConduit,
  submission_terminal: createSubmissionTerminal,
  containment_trap: createContainmentTrap,
  purification_beacon: createPurificationBeacon,
  defense_turret: createDefenseTurret,
  claim_beacon: createClaimBeacon,
  trade_terminal: createTradeTerminal,
  crossover: createCrossover,
  dimensional_stabilizer: createDimensionalStabilizer,
  astral_projection_chamber: createAstralProjectionChamber,
  gathering_post: createGatheringPost,
  drone_bay: createDroneBay,
  loader: createLoader,
  unloader: createUnloader,
  mixer: createMixer,
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
