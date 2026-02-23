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

  // Creature / fuel
  biofuel: 0x66aa44,
  refined_fuel: 0x33aaaa,
  creature_essence: 0xaa44cc,
  hiss_residue: 0xff2244,
};

const ITEM_SCALE = 0.003;
const ITEM_HEIGHT = 1.004; // Above sphere surface (just above buildings at 1.001)

/**
 * ItemRenderer manages the 3D meshes for items on conveyors and in building buffers.
 * Uses an object pool to avoid creating/destroying meshes every frame.
 */
export class ItemRenderer {
  constructor(scene, getTileCenter, chunkManager) {
    this.scene = scene;
    this.getTileCenter = getTileCenter;
    this.chunkManager = chunkManager;
    this.pool = [];
    this.active = new Map(); // key -> mesh
    this.sharedGeometry = new THREE.SphereGeometry(ITEM_SCALE, 6, 6);
    this.materials = {};

    for (const [type, color] of Object.entries(ITEM_COLORS)) {
      this.materials[type] = new THREE.MeshLambertMaterial({ color });
    }
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

      // Update material if item type changed
      const mat = this.materials[item.item];
      if (mat && mesh.material !== mat) {
        mesh.material = mat;
      }

      // Compute interpolated world position
      const destPos = this.getTileCenter(item.face, item.row, item.col);

      if (item.fromFace != null && item.t < 1.0) {
        const srcPos = this.getTileCenter(item.fromFace, item.fromRow, item.fromCol);
        // Lerp and re-normalize for smooth spherical movement
        const pos = new THREE.Vector3().lerpVectors(srcPos, destPos, item.t);
        pos.normalize();
        mesh.position.copy(pos).multiplyScalar(ITEM_HEIGHT);
      } else {
        mesh.position.copy(destPos).multiplyScalar(ITEM_HEIGHT);
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
    if (this.pool.length > 0) {
      const mesh = this.pool.pop();
      mesh.material = this.materials[itemType] || this.materials.iron_ore;
      return mesh;
    }

    const mat = this.materials[itemType] || this.materials.iron_ore;
    const mesh = new THREE.Mesh(this.sharedGeometry, mat);
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
    this.sharedGeometry.dispose();
    for (const mat of Object.values(this.materials)) {
      mat.dispose();
    }
  }
}
