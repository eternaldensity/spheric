import * as THREE from "three";

/**
 * Creature type colors (matching backend creature_types).
 */
const CREATURE_COLORS = {
  ember_wisp: 0xff6622,
  frost_shard: 0x88ccff,
  quartz_drone: 0xd4b8ff,
  shadow_tendril: 0x332244,
  copper_beetle: 0xdd8844,
  spore_cloud: 0x66aa44,
  static_mote: 0xffff44,
  void_fragment: 0x220044,
};

const CREATURE_SCALE = 0.004;
const CREATURE_HEIGHT = 1.015; // Above sphere, below items

/**
 * CreatureRenderer manages the 3D meshes for wild creatures on the sphere.
 * Uses an object pool to avoid creating/destroying meshes every frame.
 * Creatures bob and rotate gently for visual life.
 */
export class CreatureRenderer {
  constructor(scene, getTileCenter) {
    this.scene = scene;
    this.getTileCenter = getTileCenter;
    this.pool = [];
    this.active = new Map(); // creature_id -> { mesh, data }
    this.materials = {};
    this.time = 0;

    // Shared geometries for creature shapes
    this.geometries = {
      // Default: octahedron (crystal-like)
      default: new THREE.OctahedronGeometry(CREATURE_SCALE, 0),
      // Wisp: small sphere
      wisp: new THREE.SphereGeometry(CREATURE_SCALE * 0.8, 6, 6),
      // Beetle: box
      beetle: new THREE.BoxGeometry(
        CREATURE_SCALE * 1.2,
        CREATURE_SCALE * 0.6,
        CREATURE_SCALE * 1.0
      ),
      // Cloud: sphere (larger, semi-transparent)
      cloud: new THREE.SphereGeometry(CREATURE_SCALE * 1.2, 8, 8),
    };

    // Create materials for each creature type
    for (const [type, color] of Object.entries(CREATURE_COLORS)) {
      const isTransparent = type === "spore_cloud" || type === "shadow_tendril";
      this.materials[type] = new THREE.MeshLambertMaterial({
        color,
        transparent: isTransparent,
        opacity: isTransparent ? 0.7 : 1.0,
        emissive: new THREE.Color(color).multiplyScalar(0.3),
      });
    }
  }

  /**
   * Get the appropriate geometry for a creature type.
   */
  getGeometry(type) {
    switch (type) {
      case "ember_wisp":
      case "frost_shard":
      case "static_mote":
        return this.geometries.wisp;
      case "copper_beetle":
        return this.geometries.beetle;
      case "spore_cloud":
        return this.geometries.cloud;
      default:
        return this.geometries.default;
    }
  }

  /**
   * Update creature visuals from server sync data.
   * @param {Array} creatures - array of { id, type, face, row, col }
   */
  update(creatures, deltaTime) {
    this.time += deltaTime;

    const activeIds = new Set();

    for (const c of creatures) {
      activeIds.add(c.id);

      let entry = this.active.get(c.id);
      if (!entry) {
        const mesh = this.acquireMesh(c.type);
        entry = { mesh, data: c };
        this.active.set(c.id, entry);
      }

      // Update data
      entry.data = c;

      // Update material if type changed
      const mat = this.materials[c.type];
      if (mat && entry.mesh.material !== mat) {
        entry.mesh.material = mat;
      }

      // Update geometry if type changed
      const geo = this.getGeometry(c.type);
      if (geo && entry.mesh.geometry !== geo) {
        entry.mesh.geometry = geo;
      }

      // Position on sphere
      const pos = this.getTileCenter(c.face, c.row, c.col);
      if (pos) {
        const normal = pos.clone().normalize();

        // Bob up and down gently
        const bobOffset =
          Math.sin(this.time * 3 + c.id.charCodeAt(9) * 0.5) * 0.001;
        entry.mesh.position
          .copy(normal)
          .multiplyScalar(CREATURE_HEIGHT + bobOffset);

        // Gentle rotation
        entry.mesh.rotation.y += deltaTime * 1.5;
      }

      entry.mesh.visible = true;
    }

    // Return unused meshes to pool
    for (const [id, entry] of this.active) {
      if (!activeIds.has(id)) {
        entry.mesh.visible = false;
        this.pool.push(entry.mesh);
        this.active.delete(id);
      }
    }
  }

  acquireMesh(type) {
    const mat = this.materials[type] || this.materials.ember_wisp;
    const geo = this.getGeometry(type);

    if (this.pool.length > 0) {
      const mesh = this.pool.pop();
      mesh.material = mat;
      mesh.geometry = geo;
      return mesh;
    }

    const mesh = new THREE.Mesh(geo, mat);
    this.scene.add(mesh);
    return mesh;
  }

  /**
   * Handle a creature spawn event (add immediately).
   */
  onCreatureSpawned(id, creature) {
    if (this.active.has(id)) return;

    const mesh = this.acquireMesh(creature.type);
    const pos = this.getTileCenter(creature.face, creature.row, creature.col);
    if (pos) {
      const normal = pos.clone().normalize();
      mesh.position.copy(normal).multiplyScalar(CREATURE_HEIGHT);
    }
    mesh.visible = true;
    this.active.set(id, { mesh, data: creature });
  }

  /**
   * Handle a creature move event (update position).
   */
  onCreatureMoved(id, creature) {
    const entry = this.active.get(id);
    if (entry) {
      entry.data = creature;
      // Position update happens in next update() call
    } else {
      this.onCreatureSpawned(id, creature);
    }
  }

  /**
   * Handle a creature capture event (remove from scene).
   */
  onCreatureCaptured(id) {
    const entry = this.active.get(id);
    if (entry) {
      entry.mesh.visible = false;
      this.pool.push(entry.mesh);
      this.active.delete(id);
    }
  }

  dispose() {
    for (const [, entry] of this.active) {
      this.scene.remove(entry.mesh);
    }
    for (const mesh of this.pool) {
      this.scene.remove(mesh);
    }
    for (const geo of Object.values(this.geometries)) {
      geo.dispose();
    }
    for (const mat of Object.values(this.materials)) {
      mat.dispose();
    }
  }
}
