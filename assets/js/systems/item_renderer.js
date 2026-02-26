import * as THREE from "three";

export const ITEM_COLORS = {
  // Raw ores
  iron_ore: 0xd4722a,
  copper_ore: 0x30c9a8,
  raw_quartz: 0xd4b8ff,
  titanium_ore: 0x556677,
  crude_oil: 0x1a1a2e,
  raw_sulfur: 0xcccc22,
  raw_uranium: 0x55ff55,

  // Tier 0-1 processed
  iron_ingot: 0xaaaaaa,
  copper_ingot: 0xdd8844,
  titanium_ingot: 0x8899aa,
  polycarbonate: 0x88bbdd,
  sulfur_compound: 0xaaaa44,
  wire: 0xdd8844,
  plate: 0xbbbbbb,
  circuit: 0x44ff88,
  frame: 0x667788,
  quartz_crystal: 0xc8aaff,

  // Tier 2-3 processed
  motor: 0x99aacc,
  cable: 0xcc6622,
  reinforced_plate: 0xccccdd,
  heat_sink: 0x4488cc,
  heavy_frame: 0x556688,
  advanced_circuit: 0x22cc66,
  plastic_sheet: 0xddeeff,

  // Tier 4-5 processed
  computer: 0x33aa88,
  motor_housing: 0x778899,
  composite: 0x8899aa,
  supercomputer: 0x22ddaa,
  advanced_composite: 0x6677aa,

  // Tier 6-8
  enriched_uranium: 0x33ff33,
  nuclear_cell: 0x44ff66,
  containment_module: 0x8844cc,
  dimensional_core: 0xaa44ff,
  astral_lens: 0xcc88ff,
  board_resonator: 0xff88cc,

  // Whispering chain
  whispering_powder: 0xc8b8d8,
  whispering_ingot: 0xa090c0,

  // Cryogenic / fluid
  ice: 0xcceeff,
  thermal_slurry: 0xff6633,
  water: 0x3399dd,
  coolant_cube: 0x88ddff,

  // Creature / fuel
  biofuel: 0x66aa44,
  catalysed_fuel: 0xcc8822,
  refined_fuel: 0x33aaaa,
  unstable_fuel: 0xb9173a,
  stable_fuel: 0x02662b,
  creature_essence: 0xaa44cc,
  hiss_residue: 0xff2244,
};

const ITEM_SCALE = 0.003;
const ITEM_HEIGHT = 1.004; // Above sphere surface (just above buildings at 1.001)

// --- Shared geometries for shaped item types ---

function createIngotGeometry() {
  // Flat rectangular prism with beveled top edges via ExtrudeGeometry
  const s = ITEM_SCALE;
  const hw = s * 0.7; // half-width
  const hd = s * 0.4; // half-depth
  const shape = new THREE.Shape();
  shape.moveTo(-hw, -hd);
  shape.lineTo(hw, -hd);
  shape.lineTo(hw, hd);
  shape.lineTo(-hw, hd);
  shape.closePath();
  const geo = new THREE.ExtrudeGeometry(shape, {
    depth: s * 0.5,
    bevelEnabled: true,
    bevelThickness: s * 0.15,
    bevelSize: s * 0.12,
    bevelSegments: 1,
  });
  // Center vertically — extrude goes 0..depth on Z, shift to center
  geo.translate(0, 0, -s * 0.25);
  // Rotate so the flat face is in XZ plane (Y = up/radial)
  geo.rotateX(-Math.PI / 2);
  return geo;
}

function createPlateGeometry() {
  // Wide thin flat box
  const s = ITEM_SCALE;
  return new THREE.BoxGeometry(s * 1.6, s * 0.2, s * 1.2);
}

function createWireGeometry() {
  // Small torus — coil of wire
  const s = ITEM_SCALE;
  return new THREE.TorusGeometry(s * 0.5, s * 0.15, 6, 10);
}

function createFrameGeometry() {
  // Open rectangular frame — outer box with hollow center via ExtrudeGeometry
  const s = ITEM_SCALE;
  const ow = s * 0.8; // outer half-width
  const od = s * 0.6; // outer half-depth
  const t = s * 0.15; // bar thickness

  const outer = new THREE.Shape();
  outer.moveTo(-ow, -od);
  outer.lineTo(ow, -od);
  outer.lineTo(ow, od);
  outer.lineTo(-ow, od);
  outer.closePath();

  const hole = new THREE.Path();
  hole.moveTo(-ow + t, -od + t);
  hole.lineTo(ow - t, -od + t);
  hole.lineTo(ow - t, od - t);
  hole.lineTo(-ow + t, od - t);
  hole.closePath();
  outer.holes.push(hole);

  const geo = new THREE.ExtrudeGeometry(outer, {
    depth: s * 0.6,
    bevelEnabled: false,
  });
  geo.translate(0, 0, -s * 0.3);
  geo.rotateX(-Math.PI / 2);
  return geo;
}

// Build geometry lookup — shaped types get custom geometry, rest get default sphere
const _shapedGeometries = {
  iron_ingot: createIngotGeometry(),
  copper_ingot: createIngotGeometry(),
  titanium_ingot: createIngotGeometry(),
  whispering_ingot: createIngotGeometry(),
  plate: createPlateGeometry(),
  reinforced_plate: createPlateGeometry(),
  plastic_sheet: createPlateGeometry(),
  wire: createWireGeometry(),
  cable: createWireGeometry(),
  frame: createFrameGeometry(),
  heavy_frame: createFrameGeometry(),
};

// Items with shaped geometry need radial + conveyor-facing orientation
const _shapedTypes = new Set(Object.keys(_shapedGeometries));

// Direction offsets: orientation 0-3 -> [dRow, dCol]
// Must match DIR_OFFSETS in game_renderer.js
const DIR_OFFSETS = [
  [0, 1],   // 0: col+1
  [1, 0],   // 1: row+1
  [0, -1],  // 2: col-1
  [-1, 0],  // 3: row-1
];

// Reusable temp objects for orientation math (avoid per-frame allocation)
const _normal = new THREE.Vector3();
const _tangentX = new THREE.Vector3();
const _tangentZ = new THREE.Vector3();
const _mat4 = new THREE.Matrix4();
const _up = new THREE.Vector3(0, 1, 0);
const _quat = new THREE.Quaternion();

/**
 * ItemRenderer manages the 3D meshes for items on conveyors and in building buffers.
 * Uses an object pool to avoid creating/destroying meshes every frame.
 */
export class ItemRenderer {
  constructor(scene, getTileCenter, chunkManager, buildingData) {
    this.scene = scene;
    this.getTileCenter = getTileCenter;
    this.chunkManager = chunkManager;
    this.buildingData = buildingData; // Map<"face:row:col", {type, orientation}>
    this.pool = [];
    this.active = new Map(); // key -> mesh
    this.defaultGeometry = new THREE.SphereGeometry(ITEM_SCALE, 6, 6);
    this.materials = {};

    for (const [type, color] of Object.entries(ITEM_COLORS)) {
      this.materials[type] = new THREE.MeshLambertMaterial({ color });
    }
  }

  _getGeometry(itemType) {
    return _shapedGeometries[itemType] || this.defaultGeometry;
  }

  /**
   * Update item visuals based on interpolated positions.
   * @param {Array} interpolatedItems - from ItemInterpolator.getInterpolatedItems()
   */
  update(interpolatedItems) {
    const usedKeys = new Set();

    for (const item of interpolatedItems) {
      const key = `${item.face}:${item.row}:${item.col}:${item.item}`;
      usedKeys.add(key);

      let mesh = this.active.get(key);
      if (!mesh) {
        mesh = this.acquireMesh(item.item);
        this.active.set(key, mesh);
      }

      // Update material and geometry if item type changed
      const mat = this.materials[item.item];
      if (mat && mesh.material !== mat) mesh.material = mat;
      const geo = this._getGeometry(item.item);
      if (mesh.geometry !== geo) mesh.geometry = geo;

      // Compute interpolated world position
      const destPos = this.getTileCenter(item.face, item.row, item.col);
      let worldPos;

      if (item.fromFace != null && item.t < 1.0) {
        const srcPos = this.getTileCenter(item.fromFace, item.fromRow, item.fromCol);
        // Lerp and re-normalize for smooth spherical movement
        worldPos = new THREE.Vector3().lerpVectors(srcPos, destPos, item.t);
        worldPos.normalize();
      } else {
        worldPos = destPos.clone().normalize();
      }

      mesh.position.copy(worldPos).multiplyScalar(ITEM_HEIGHT);

      // Orient shaped items: radial up + align to conveyor direction
      if (_shapedTypes.has(item.item)) {
        const bldKey = `${item.face}:${item.row}:${item.col}`;
        const bld = this.buildingData.get(bldKey);
        if (bld != null && bld.orientation != null) {
          // Same approach as building orientation in game_renderer.js:
          // compute tangent-plane forward from tile toward its output neighbor
          _normal.copy(worldPos);
          const [dr, dc] = DIR_OFFSETS[bld.orientation];
          const neighborCenter = this.getTileCenter(item.face, item.row + dr, item.col + dc);
          _tangentX.subVectors(neighborCenter, _normal);
          _tangentX.addScaledVector(_normal, -_tangentX.dot(_normal)).normalize();
          _tangentZ.crossVectors(_tangentX, _normal).normalize();
          _mat4.makeBasis(_tangentX, _normal, _tangentZ);
          mesh.quaternion.setFromRotationMatrix(_mat4);
        } else {
          // No conveyor — just face radially outward
          _quat.setFromUnitVectors(_up, worldPos);
          mesh.quaternion.copy(_quat);
        }
      }

      mesh.visible = this.chunkManager.isTileVisible(item.face, item.row, item.col);
    }

    // Return unused meshes to pool
    for (const [key, mesh] of this.active) {
      if (!usedKeys.has(key)) {
        mesh.visible = false;
        this.pool.push(mesh);
        this.active.delete(key);
      }
    }
  }

  acquireMesh(itemType) {
    const geo = this._getGeometry(itemType);
    const mat = this.materials[itemType] || this.materials.iron_ore;

    if (this.pool.length > 0) {
      const mesh = this.pool.pop();
      mesh.geometry = geo;
      mesh.material = mat;
      mesh.quaternion.identity();
      return mesh;
    }

    const mesh = new THREE.Mesh(geo, mat);
    this.scene.add(mesh);
    return mesh;
  }

  dispose() {
    for (const [, mesh] of this.active) {
      this.scene.remove(mesh);
    }
    for (const mesh of this.pool) {
      this.scene.remove(mesh);
    }
    this.defaultGeometry.dispose();
    for (const geo of Object.values(_shapedGeometries)) {
      geo.dispose();
    }
    for (const mat of Object.values(this.materials)) {
      mat.dispose();
    }
  }
}
