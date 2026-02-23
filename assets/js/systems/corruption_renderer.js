import * as THREE from "three";

const MAX_CORRUPTION_INSTANCES = 2000;
const MAX_HISS_INSTANCES = 50;

const _tempMatrix = new THREE.Matrix4();
const _tempPosition = new THREE.Vector3();
const _tempQuaternion = new THREE.Quaternion();
const _tempScale = new THREE.Vector3(1, 1, 1);
const _up = new THREE.Vector3(0, 0, 1);
const _color = new THREE.Color();

/**
 * CorruptionRenderer manages Hiss corruption overlays and Hiss entity meshes.
 * Uses InstancedMesh for O(1) draw calls regardless of corruption count.
 */
export class CorruptionRenderer {
  constructor(scene, getTileCenter, subdivisions, chunkManager) {
    this.scene = scene;
    this.getTileCenter = getTileCenter;
    this.subdivisions = subdivisions;
    this.chunkManager = chunkManager;

    // Corruption data: "face:row:col" -> { intensity, phase, index }
    this.corruptionData = new Map();
    this._dirty = true; // needs rebuild
    this._instanceCount = 0;

    // Shared geometry/material for all corruption overlays (single draw call)
    const tileSize = (1.0 / subdivisions) * 0.9;
    this._overlayGeometry = new THREE.PlaneGeometry(tileSize, tileSize);
    this._overlayMaterial = new THREE.MeshBasicMaterial({
      color: 0xff1111,
      transparent: true,
      opacity: 0.4,
      depthWrite: false,
      side: THREE.DoubleSide,
    });

    this._instancedMesh = new THREE.InstancedMesh(
      this._overlayGeometry,
      this._overlayMaterial,
      MAX_CORRUPTION_INSTANCES
    );
    this._instancedMesh.count = 0;
    this._instancedMesh.frustumCulled = false;
    this.scene.add(this._instancedMesh);

    // Per-instance phase offsets for pulsing animation (stored in a flat array)
    this._phases = new Float32Array(MAX_CORRUPTION_INSTANCES);
    // Per-instance base alpha values
    this._baseAlphas = new Float32Array(MAX_CORRUPTION_INSTANCES);

    // Hiss entities
    this.hissEntityData = [];
    this.hissEntityMeshes = new Map();

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
    const existing = this.corruptionData.get(key);
    if (existing) {
      // Just update intensity, will rebuild on next frame
      existing.intensity = intensity;
    } else {
      this.corruptionData.set(key, {
        face, row, col, intensity,
        phase: Math.random() * Math.PI * 2,
      });
    }
    this._dirty = true;
  }

  removeOverlay(face, row, col) {
    const key = `${face}:${row}:${col}`;
    this.corruptionData.delete(key);
    this._dirty = true;
  }

  syncFace(face, tiles) {
    // Remove all entries for this face
    for (const [key] of this.corruptionData) {
      if (key.startsWith(`${face}:`)) {
        this.corruptionData.delete(key);
      }
    }
    // Add new entries
    for (const tile of tiles) {
      const key = `${tile.face}:${tile.row}:${tile.col}`;
      this.corruptionData.set(key, {
        face: tile.face, row: tile.row, col: tile.col,
        intensity: tile.intensity,
        phase: Math.random() * Math.PI * 2,
      });
    }
    this._dirty = true;
  }

  /**
   * Rebuild the instanced mesh transforms from corruption data.
   * Only called when data changes (not every frame).
   */
  _rebuildInstances() {
    let idx = 0;
    for (const [, data] of this.corruptionData) {
      if (idx >= MAX_CORRUPTION_INSTANCES) break;

      const center = this.getTileCenter(data.face, data.row, data.col);
      if (!center) continue;

      _tempPosition.copy(center).normalize().multiplyScalar(1.002);
      _tempQuaternion.setFromUnitVectors(_up, _tempPosition.clone().normalize());
      _tempMatrix.compose(_tempPosition, _tempQuaternion, _tempScale);
      this._instancedMesh.setMatrixAt(idx, _tempMatrix);

      this._phases[idx] = data.phase;
      this._baseAlphas[idx] = 0.15 + (data.intensity / 10) * 0.45;
      idx++;
    }

    this._instanceCount = idx;
    this._instancedMesh.count = idx;
    this._instancedMesh.instanceMatrix.needsUpdate = true;
    this._dirty = false;
  }

  updateOverlays(now) {
    if (this._dirty) {
      this._rebuildInstances();
    }

    // Pulse the global material opacity based on average —
    // individual per-instance opacity isn't supported by InstancedMesh,
    // so we do a single global pulse which is much cheaper
    const t = now * 0.001;
    const pulse = 0.8 + 0.2 * Math.sin(t * 2.0);
    this._overlayMaterial.opacity = 0.35 * pulse;
  }

  // --- Hiss entity management ---

  syncHissEntities(face, entities) {
    for (const [id, mesh] of this.hissEntityMeshes) {
      const data = this.hissEntityData.find((e) => e.id === id);
      if (data && data.face === face) {
        this.scene.remove(mesh);
        this.hissEntityMeshes.delete(id);
      }
    }
    this.hissEntityData = this.hissEntityData.filter((e) => e.face !== face);
    this.hissEntityData.push(...entities);
  }

  addHissEntity(id, entity) {
    this.hissEntityData.push({ id, ...entity });
  }

  moveHissEntity(id, entity) {
    const idx = this.hissEntityData.findIndex((e) => e.id === id);
    if (idx >= 0) {
      this.hissEntityData[idx] = { id, ...entity };
    } else {
      this.hissEntityData.push({ id, ...entity });
    }
  }

  killHissEntity(id) {
    this.hissEntityData = this.hissEntityData.filter((e) => e.id !== id);
    const mesh = this.hissEntityMeshes.get(id);
    if (mesh) {
      this.scene.remove(mesh);
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

      const visible = this.chunkManager.isTileVisible(entity.face, entity.row, entity.col);
      mesh.visible = visible;
      if (!visible) continue;

      const center = this.getTileCenter(entity.face, entity.row, entity.col);
      if (center) {
        const target = center.clone().normalize().multiplyScalar(1.012);
        mesh.position.lerp(target, 0.15);
      }

      mesh.rotation.x += 0.03;
      mesh.rotation.y += 0.02;
    }

    // Remove meshes for entities that no longer exist
    const activeIds = new Set(this.hissEntityData.map((e) => e.id));
    for (const [id, mesh] of this.hissEntityMeshes) {
      if (!activeIds.has(id)) {
        this.scene.remove(mesh);
        this.hissEntityMeshes.delete(id);
      }
    }
  }

  dispose() {
    if (this._instancedMesh) {
      this.scene.remove(this._instancedMesh);
      this._instancedMesh.dispose();
      this._instancedMesh = null;
    }
    if (this._overlayGeometry) {
      this._overlayGeometry.dispose();
      this._overlayGeometry = null;
    }
    if (this._overlayMaterial) {
      this._overlayMaterial.dispose();
      this._overlayMaterial = null;
    }
    this.corruptionData.clear();

    for (const [, mesh] of this.hissEntityMeshes) {
      this.scene.remove(mesh);
    }
    this.hissEntityMeshes.clear();
    this.hissEntityData = [];

    if (this._hissGeometry) {
      this._hissGeometry.dispose();
      this._hissGeometry = null;
    }
    if (this._hissMaterial) {
      this._hissMaterial.dispose();
      this._hissMaterial = null;
    }
  }
}
