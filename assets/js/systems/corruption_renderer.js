import * as THREE from "three";

/**
 * CorruptionRenderer manages Hiss corruption overlays and Hiss entity meshes.
 */
export class CorruptionRenderer {
  constructor(scene, getTileCenter, subdivisions) {
    this.scene = scene;
    this.getTileCenter = getTileCenter;
    this.subdivisions = subdivisions;

    this.corruptionData = new Map();   // "face:row:col" -> { intensity }
    this.corruptionMeshes = new Map(); // "face:row:col" -> THREE.Mesh

    this.hissEntityData = [];          // current Hiss entity data for rendering
    this.hissEntityMeshes = new Map(); // id -> THREE.Mesh

    this._hissGeometry = new THREE.OctahedronGeometry(0.006, 0);
    this._hissMaterial = new THREE.MeshStandardMaterial({
      color: 0xff2222,
      emissive: 0xcc0000,
      emissiveIntensity: 0.6,
      transparent: true,
      opacity: 0.85,
      metalness: 0.5,
      roughness: 0.3,
    });
  }

  addOverlay(face, row, col, intensity) {
    const key = `${face}:${row}:${col}`;
    this.corruptionData.set(key, { intensity });

    if (this.corruptionMeshes.has(key)) {
      this.scene.remove(this.corruptionMeshes.get(key));
    }

    const center = this.getTileCenter(face, row, col);
    if (!center) return;

    const normal = center.clone().normalize();
    const alpha = 0.15 + (intensity / 10) * 0.45;
    const N = this.subdivisions;
    const tileSize = 1.0 / N * 0.9;

    const geo = new THREE.PlaneGeometry(tileSize, tileSize);
    const mat = new THREE.MeshBasicMaterial({
      color: 0xff1111,
      transparent: true,
      opacity: alpha,
      depthWrite: false,
      side: THREE.DoubleSide,
    });

    const mesh = new THREE.Mesh(geo, mat);
    mesh.position.copy(normal).multiplyScalar(1.002);
    mesh.quaternion.setFromUnitVectors(
      new THREE.Vector3(0, 0, 1), normal
    );

    mesh.userData.intensity = intensity;
    mesh.userData.phase = Math.random() * Math.PI * 2;
    this.scene.add(mesh);
    this.corruptionMeshes.set(key, mesh);
  }

  removeOverlay(face, row, col) {
    const key = `${face}:${row}:${col}`;
    const mesh = this.corruptionMeshes.get(key);
    if (mesh) {
      this.scene.remove(mesh);
      mesh.geometry.dispose();
      mesh.material.dispose();
      this.corruptionMeshes.delete(key);
    }
    this.corruptionData.delete(key);
  }

  syncFace(face, tiles) {
    // Remove old corruption meshes for this face
    for (const [key, mesh] of this.corruptionMeshes) {
      if (key.startsWith(`${face}:`)) {
        this.scene.remove(mesh);
        this.corruptionMeshes.delete(key);
        this.corruptionData.delete(key);
      }
    }
    for (const tile of tiles) {
      this.addOverlay(tile.face, tile.row, tile.col, tile.intensity);
    }
  }

  updateOverlays(now) {
    const t = now * 0.001;
    for (const [, mesh] of this.corruptionMeshes) {
      const intensity = mesh.userData.intensity || 1;
      const baseAlpha = 0.15 + (intensity / 10) * 0.45;
      const pulse = 0.8 + 0.2 * Math.sin(t * 3.0 + mesh.userData.phase);
      mesh.material.opacity = baseAlpha * pulse;
    }
  }

  // --- Hiss entity management ---

  syncHissEntities(face, entities) {
    for (const [id, mesh] of this.hissEntityMeshes) {
      const data = this.hissEntityData.find(e => e.id === id);
      if (data && data.face === face) {
        this.scene.remove(mesh);
        // geometry/material are shared — don't dispose per-mesh
        this.hissEntityMeshes.delete(id);
      }
    }
    this.hissEntityData = this.hissEntityData.filter(e => e.face !== face);
    this.hissEntityData.push(...entities);
  }

  addHissEntity(id, entity) {
    this.hissEntityData.push({ id, ...entity });
  }

  moveHissEntity(id, entity) {
    const idx = this.hissEntityData.findIndex(e => e.id === id);
    if (idx >= 0) {
      this.hissEntityData[idx] = { id, ...entity };
    } else {
      this.hissEntityData.push({ id, ...entity });
    }
  }

  killHissEntity(id) {
    this.hissEntityData = this.hissEntityData.filter(e => e.id !== id);
    const mesh = this.hissEntityMeshes.get(id);
    if (mesh) {
      this.scene.remove(mesh);
      // geometry/material are shared — don't dispose per-mesh
      this.hissEntityMeshes.delete(id);
    }
  }

  updateHissEntities() {
    for (const entity of this.hissEntityData) {
      let mesh = this.hissEntityMeshes.get(entity.id);
      if (!mesh) {
        mesh = new THREE.Mesh(this._hissGeometry, this._hissMaterial);
        this.scene.add(mesh);
        this.hissEntityMeshes.set(entity.id, mesh);
      }

      const center = this.getTileCenter(entity.face, entity.row, entity.col);
      if (center) {
        const target = center.clone().normalize().multiplyScalar(1.012);
        mesh.position.lerp(target, 0.15);
      }

      mesh.rotation.x += 0.03;
      mesh.rotation.y += 0.02;
    }

    // Remove meshes for entities that no longer exist
    const activeIds = new Set(this.hissEntityData.map(e => e.id));
    for (const [id, mesh] of this.hissEntityMeshes) {
      if (!activeIds.has(id)) {
        this.scene.remove(mesh);
        this.hissEntityMeshes.delete(id);
      }
    }
  }

  dispose() {
    for (const [, mesh] of this.corruptionMeshes) {
      this.scene.remove(mesh);
      mesh.geometry.dispose();
      mesh.material.dispose();
    }
    this.corruptionMeshes.clear();
    this.corruptionData.clear();

    for (const [, mesh] of this.hissEntityMeshes) {
      this.scene.remove(mesh);
    }
    this.hissEntityMeshes.clear();
    this.hissEntityData = [];

    if (this._hissGeometry) { this._hissGeometry.dispose(); this._hissGeometry = null; }
    if (this._hissMaterial) { this._hissMaterial.dispose(); this._hissMaterial = null; }
  }
}
