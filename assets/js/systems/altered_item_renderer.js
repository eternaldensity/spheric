import * as THREE from "three";

/**
 * AlteredItemRenderer manages the glowing octahedron meshes for altered items.
 */
export class AlteredItemRenderer {
  constructor(scene, getTileCenter, chunkManager) {
    this.scene = scene;
    this.getTileCenter = getTileCenter;
    this.chunkManager = chunkManager;
    this.items = new Map();  // "face:row:col" -> { type, color }
    this.meshes = new Map(); // "face:row:col" -> THREE.Mesh
    this._time = 0;
  }

  addItem(face, row, col, type, colorHex) {
    const key = `${face}:${row}:${col}`;
    if (this.meshes.has(key)) return;

    const center = this.getTileCenter(face, row, col);
    if (!center) return;

    const geo = new THREE.OctahedronGeometry(0.005, 0);
    const mat = new THREE.MeshStandardMaterial({
      color: colorHex,
      emissive: colorHex,
      emissiveIntensity: 0.5,
      transparent: true,
      opacity: 0.85,
      metalness: 0.3,
      roughness: 0.4,
    });

    const mesh = new THREE.Mesh(geo, mat);
    const pos = center.clone().normalize().multiplyScalar(1.01);
    mesh.position.copy(pos);
    mesh.userData.phase = Math.random() * Math.PI * 2;
    this.scene.add(mesh);
    this.meshes.set(key, mesh);
    this.items.set(key, { type, color: colorHex });
  }

  removeItem(face, row, col) {
    const key = `${face}:${row}:${col}`;
    const mesh = this.meshes.get(key);
    if (mesh) {
      this.scene.remove(mesh);
      mesh.geometry.dispose();
      mesh.material.dispose();
      this.meshes.delete(key);
    }
    this.items.delete(key);
  }

  update() {
    this._time += 0.016;
    for (const [key, mesh] of this.meshes) {
      const item = this.items.get(key);
      if (!item || !mesh) continue;

      const parts = key.split(":");
      const visible = this.chunkManager.isTileVisible(
        parseInt(parts[0]), parseInt(parts[1]), parseInt(parts[2])
      );
      mesh.visible = visible;
      if (!visible) continue;

      mesh.rotation.x += 0.01;
      mesh.rotation.y += 0.015;
      const pulse = 0.4 + 0.6 * Math.sin(this._time * 2.0 + mesh.userData.phase);
      mesh.material.emissiveIntensity = pulse;
    }
  }

  dispose() {
    for (const [, mesh] of this.meshes) {
      this.scene.remove(mesh);
      mesh.geometry.dispose();
      mesh.material.dispose();
    }
    this.meshes.clear();
    this.items.clear();
  }
}
