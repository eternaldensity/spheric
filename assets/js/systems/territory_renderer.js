import * as THREE from "three";

/**
 * TerritoryRenderer draws border overlays for player territory zones.
 */
export class TerritoryRenderer {
  constructor(scene, getTileCenter, subdivisions) {
    this.scene = scene;
    this.getTileCenter = getTileCenter;
    this.subdivisions = subdivisions;
    this.data = new Map();   // face_id -> territories array
    this.meshes = new Map(); // "face:row:col" -> THREE.Mesh
  }

  setTerritories(faceId, territories) {
    this.data.set(faceId, territories);
    this._rebuild(faceId);
  }

  _rebuild(faceId) {
    // Remove existing territory meshes for this face
    for (const [key, mesh] of this.meshes) {
      if (key.startsWith(`${faceId}:`)) {
        this.scene.remove(mesh);
        mesh.geometry.dispose();
        mesh.material.dispose();
        this.meshes.delete(key);
      }
    }

    const territories = this.data.get(faceId);
    if (!territories || territories.length === 0) return;

    const N = this.subdivisions;

    for (const t of territories) {
      const r = t.radius;
      const color = this._ownerColor(t.owner_id);

      for (let row = t.center_row - r; row <= t.center_row + r; row++) {
        for (let col = t.center_col - r; col <= t.center_col + r; col++) {
          if (row < 0 || row >= N || col < 0 || col >= N) continue;

          const onBorder =
            row === t.center_row - r || row === t.center_row + r ||
            col === t.center_col - r || col === t.center_col + r;
          if (!onBorder) continue;

          const key = `${faceId}:${row}:${col}`;
          if (this.meshes.has(key)) continue;

          const center = this.getTileCenter(faceId, row, col);
          if (!center) continue;

          const normal = center.clone().normalize();
          const tileSize = 1.0 / N * 0.9;

          const geo = new THREE.PlaneGeometry(tileSize, tileSize);
          const mat = new THREE.MeshBasicMaterial({
            color: color,
            transparent: true,
            opacity: 0.2,
            depthWrite: false,
            side: THREE.DoubleSide,
          });

          const mesh = new THREE.Mesh(geo, mat);
          mesh.position.copy(normal).multiplyScalar(1.001);
          mesh.quaternion.setFromUnitVectors(
            new THREE.Vector3(0, 0, 1), normal
          );

          this.scene.add(mesh);
          this.meshes.set(key, mesh);
        }
      }
    }
  }

  _ownerColor(ownerId) {
    let hash = 0;
    for (let i = 0; i < ownerId.length; i++) {
      hash = ((hash << 5) - hash) + ownerId.charCodeAt(i);
      hash |= 0;
    }
    const hue = Math.abs(hash % 360);
    return new THREE.Color(`hsl(${hue}, 60%, 50%)`);
  }

  dispose() {
    for (const [, mesh] of this.meshes) {
      this.scene.remove(mesh);
      mesh.geometry.dispose();
      mesh.material.dispose();
    }
    this.meshes.clear();
    this.data.clear();
  }
}
