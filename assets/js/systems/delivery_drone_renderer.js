import * as THREE from "three";

const S = 0.005; // Slightly smaller than player drones (0.0075)
const DRONE_HEIGHT = 1.012; // Between buildings (1.001) and items (1.004)
const MOVE_DURATION = 0.2; // seconds per tile (matches 1 tick = 200ms)

// State colors
const STATE_COLORS = {
  flying_to_storage: 0xddaa44, // amber — picking up
  flying_to_site: 0x66cc66, // green — delivering
  returning: 0x6688cc, // blue — heading back
  idle: 0x888888, // gray — shouldn't appear
};

// Item colors for cargo dots (subset of item_renderer colors)
const CARGO_COLORS = {
  iron_ingot: 0xaaaaaa,
  copper_ingot: 0xdd8844,
  titanium_ingot: 0x99bbdd,
  wire: 0xccaa55,
  plate: 0x8899aa,
  circuit: 0x44aa66,
  frame: 0x7788aa,
  motor: 0x666688,
  cable: 0xaa6644,
  heavy_frame: 0x556677,
  advanced_circuit: 0x33aa88,
  heat_sink: 0xcc6644,
  biofuel: 0x55aa33,
};
const DEFAULT_CARGO_COLOR = 0xbbbbbb;

// Shared geometries (created once)
const _geo = {
  body: new THREE.BoxGeometry(S * 0.6, S * 0.2, S * 0.6),
  arm: new THREE.BoxGeometry(S * 0.9, S * 0.06, S * 0.08),
  rotor: new THREE.CylinderGeometry(S * 0.28, S * 0.28, S * 0.03, 6),
  motor: new THREE.CylinderGeometry(S * 0.08, S * 0.1, S * 0.12, 6),
  cargo: new THREE.SphereGeometry(S * 0.15, 4, 4),
  skid: new THREE.BoxGeometry(S * 0.06, S * 0.1, S * 0.45),
};
for (const g of Object.values(_geo)) g._shared = true;

const _darkMat = new THREE.MeshLambertMaterial({ color: 0x333340 });
_darkMat._shared = true;
const _rotorMat = new THREE.MeshLambertMaterial({
  color: 0xaabbcc,
  transparent: true,
  opacity: 0.45,
});
_rotorMat._shared = true;

/**
 * DeliveryDroneRenderer manages 3D models for automated delivery drones.
 * Each drone bay with the delivery_drone upgrade gets a visible drone
 * that flies between storage vaults and construction sites.
 */
export class DeliveryDroneRenderer {
  constructor(scene, getTileCenter, chunkManager) {
    this.scene = scene;
    this.getTileCenter = getTileCenter;
    this.chunkManager = chunkManager;
    // bayKey string -> { group, accentMat, cargoMeshes, fromPos, toPos, moveT, data }
    this.active = new Map();
    this.pool = [];
    this.time = 0;
  }

  /**
   * Called when server sends delivery_drone_update event.
   * @param {number} face
   * @param {Array} drones - [{bay_face, bay_row, bay_col, face, row, col, state, cargo}]
   */
  onUpdate(face, drones) {
    const activeKeys = new Set();

    for (const d of drones) {
      const key = `${d.bay_face}_${d.bay_row}_${d.bay_col}`;
      activeKeys.add(key);

      const newPos = this.getTileCenter(d.face, d.row, d.col);
      if (!newPos) continue;

      let entry = this.active.get(key);
      if (!entry) {
        entry = this._createDrone(d.state);
        entry.fromPos = newPos.clone();
        entry.toPos = newPos.clone();
        entry.moveT = 1.0;
        entry.data = d;
        entry.face = d.face;
        this.active.set(key, entry);
        // Snap to position
        this._applyPosition(entry, newPos);
      } else {
        // Position changed — start interpolation
        if (
          d.face !== entry.data.face ||
          d.row !== entry.data.row ||
          d.col !== entry.data.col
        ) {
          entry.fromPos = entry.toPos.clone();
          entry.toPos = newPos.clone();
          entry.moveT = 0;
        }
        entry.data = d;
        entry.face = d.face;
      }

      // Update color based on state
      const color = STATE_COLORS[d.state] || STATE_COLORS.idle;
      entry.accentMat.color.setHex(color);
      entry.accentMat.emissive.setHex(color);
      entry.accentMat.emissiveIntensity = 0.3;

      // Update cargo dots
      this._updateCargo(entry, d.cargo);

      entry.group.visible = true;
    }

    // Hide drones no longer reported on this face
    for (const [key, entry] of this.active) {
      if (entry.face === face && !activeKeys.has(key)) {
        entry.group.visible = false;
        this.pool.push(entry);
        this.active.delete(key);
      }
    }
  }

  /**
   * Called every frame for smooth interpolation.
   * @param {number} dt - frame delta in seconds
   */
  tick(dt) {
    this.time += dt;

    for (const [, entry] of this.active) {
      // Advance interpolation
      if (entry.moveT < 1.0) {
        entry.moveT = Math.min(entry.moveT + dt / MOVE_DURATION, 1.0);
      }

      if (entry.fromPos && entry.toPos) {
        const t = entry.moveT;
        const smooth = t * t * (3 - 2 * t); // ease-in-out

        // Slerp on sphere surface
        const from = entry.fromPos.clone().normalize();
        const to = entry.toPos.clone().normalize();
        const interp = from.lerp(to, smooth).normalize();

        // Gentle bob
        const bob = Math.sin(this.time * 6) * 0.0005;
        entry.group.position.copy(interp).multiplyScalar(DRONE_HEIGHT + bob);

        // Face outward from sphere
        const outward = interp.clone().multiplyScalar(DRONE_HEIGHT + 1);
        entry.group.lookAt(outward);
      }

      // Visibility based on chunk
      const d = entry.data;
      if (d) {
        entry.group.visible = this.chunkManager.isTileVisible(
          d.face,
          d.row,
          d.col,
        );
      }
    }
  }

  _createDrone(state) {
    if (this.pool.length > 0) {
      const entry = this.pool.pop();
      entry.group.visible = true;
      return entry;
    }

    const group = new THREE.Group();
    const color = STATE_COLORS[state] || STATE_COLORS.idle;
    const accentMat = new THREE.MeshLambertMaterial({
      color,
      emissive: new THREE.Color(color),
      emissiveIntensity: 0.3,
    });

    // Inner drone group (rotated so Y-up maps to Z-outward after lookAt)
    const drone = new THREE.Group();
    drone.rotation.x = -Math.PI / 2;
    group.add(drone);

    // Body
    const body = new THREE.Mesh(_geo.body, accentMat);
    body.position.y = S * 0.12;
    drone.add(body);

    // 4 arms + rotors + motors
    for (let i = 0; i < 4; i++) {
      const angle = Math.PI / 4 + (Math.PI / 2) * i;

      const arm = new THREE.Mesh(_geo.arm, _darkMat);
      arm.position.set(
        Math.cos(angle) * S * 0.35,
        S * 0.12,
        Math.sin(angle) * S * 0.35,
      );
      arm.rotation.y = -angle;
      drone.add(arm);

      const motor = new THREE.Mesh(_geo.motor, _darkMat);
      motor.position.set(
        Math.cos(angle) * S * 0.7,
        S * 0.18,
        Math.sin(angle) * S * 0.7,
      );
      drone.add(motor);

      const rotor = new THREE.Mesh(_geo.rotor, _rotorMat);
      rotor.position.set(
        Math.cos(angle) * S * 0.7,
        S * 0.24,
        Math.sin(angle) * S * 0.7,
      );
      drone.add(rotor);
    }

    // Landing skids
    const skid1 = new THREE.Mesh(_geo.skid, _darkMat);
    skid1.position.set(S * -0.28, S * -0.04, 0);
    drone.add(skid1);
    const skid2 = new THREE.Mesh(_geo.skid, _darkMat);
    skid2.position.set(S * 0.28, S * -0.04, 0);
    drone.add(skid2);

    // Cargo dot meshes (up to 4, hidden by default)
    const cargoMeshes = [];
    for (let i = 0; i < 4; i++) {
      const mat = new THREE.MeshLambertMaterial({ color: DEFAULT_CARGO_COLOR });
      const mesh = new THREE.Mesh(_geo.cargo, mat);
      mesh.visible = false;
      const xOff = ((i % 2) - 0.5) * S * 0.25;
      const zOff = (Math.floor(i / 2) - 0.5) * S * 0.25;
      mesh.position.set(xOff, S * -0.1, zOff);
      drone.add(mesh);
      cargoMeshes.push(mesh);
    }

    this.scene.add(group);
    return { group, accentMat, cargoMeshes, fromPos: null, toPos: null, moveT: 1.0, data: null, face: 0 };
  }

  _applyPosition(entry, pos) {
    const outward = pos.clone().normalize();
    entry.group.position.copy(outward).multiplyScalar(DRONE_HEIGHT);
    entry.group.lookAt(outward.multiplyScalar(DRONE_HEIGHT + 1));
  }

  _updateCargo(entry, cargoItems) {
    for (let i = 0; i < entry.cargoMeshes.length; i++) {
      const mesh = entry.cargoMeshes[i];
      if (i < cargoItems.length) {
        mesh.visible = true;
        const color = CARGO_COLORS[cargoItems[i]] || DEFAULT_CARGO_COLOR;
        mesh.material.color.setHex(color);
      } else {
        mesh.visible = false;
      }
    }
  }

  dispose() {
    for (const [, entry] of this.active) {
      this.scene.remove(entry.group);
    }
    for (const entry of this.pool) {
      this.scene.remove(entry.group);
    }
    this.active.clear();
    this.pool = [];
  }
}
