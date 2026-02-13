import * as THREE from "three";

/**
 * ChunkManager handles LOD (Level of Detail) for each face of the sphere.
 *
 * Based on camera distance to each face center:
 * - Close:  full 16×16 subdivision
 * - Medium: 8×8
 * - Far:    4×4
 * - Behind: unloaded (hidden)
 *
 * Each face gets its geometry rebuilt when its LOD level changes.
 */

// LOD thresholds (camera distance to face center on unit sphere)
const LOD_CLOSE = 2.0;   // below this → full resolution
const LOD_MEDIUM = 3.5;  // below this → medium
const LOD_FAR = 5.5;     // below this → far; above → hidden

const LOD_LEVELS = {
  close: 16,
  medium: 8,
  far: 4,
};

export class ChunkManager {
  /**
   * @param {THREE.Scene} scene
   * @param {Array<THREE.Vector3>} baseVertices - 32 base polyhedron vertices
   * @param {Array<Array<number>>} faceIndices - 30 faces, each [a,b,c,d]
   * @param {number} maxSubdivisions - the full resolution subdivision count (e.g. 16)
   * @param {Array<Array<Array<{t:string, r:string|null}>>>} terrainData - per-face terrain
   * @param {object} colorConfig - { terrainColors, resourceAccents }
   */
  constructor(scene, baseVertices, faceIndices, maxSubdivisions, terrainData, colorConfig) {
    this.scene = scene;
    this.baseVertices = baseVertices;
    this.faceIndices = faceIndices;
    this.maxSubdivisions = maxSubdivisions;
    this.terrainData = terrainData;
    this.terrainColors = colorConfig.terrainColors;
    this.resourceAccents = colorConfig.resourceAccents;

    // Per-face state
    this.faceMeshes = [];      // THREE.Mesh per face (or null)
    this.faceGridLines = [];   // THREE.LineSegments per face (or null)
    this.faceEdges = [];       // { origin, e1, e2 } per face
    this.faceLOD = [];         // current LOD subdivision count per face (0 = hidden)
    this.faceColorArrays = []; // color attribute per face for overlay updates
    this.faceBaseColors = [];  // per-tile base colors per face
    this.faceOverlays = [];    // Map of overlays per face

    // Compute face centers (normalized, as THREE.Vector3)
    this.faceCenters = [];

    for (let faceId = 0; faceId < faceIndices.length; faceId++) {
      const [ai, bi, ci, di] = faceIndices[faceId];
      const A = baseVertices[ai];
      const B = baseVertices[bi];
      const C = baseVertices[ci];
      const D = baseVertices[di];

      const center = new THREE.Vector3()
        .addVectors(A, B)
        .add(C)
        .add(D)
        .multiplyScalar(0.25)
        .normalize();
      this.faceCenters.push(center);

      const e1 = new THREE.Vector3().subVectors(B, A);
      const e2 = new THREE.Vector3().subVectors(D, A);
      this.faceEdges.push({ origin: A.clone(), e1: e1.clone(), e2: e2.clone() });

      this.faceMeshes.push(null);
      this.faceGridLines.push(null);
      this.faceLOD.push(0);
      this.faceColorArrays.push(null);
      this.faceBaseColors.push(null);
      this.faceOverlays.push(new Map());
    }
  }

  /**
   * Update LOD levels based on camera position. Call each frame or throttled.
   * Returns true if any face changed LOD, so the caller can update overlays etc.
   * @param {THREE.Vector3} cameraPos
   */
  update(cameraPos) {
    let changed = false;

    for (let faceId = 0; faceId < this.faceIndices.length; faceId++) {
      const dist = cameraPos.distanceTo(this.faceCenters[faceId]);
      let targetN;

      if (dist < LOD_CLOSE) {
        targetN = LOD_LEVELS.close;
      } else if (dist < LOD_MEDIUM) {
        targetN = LOD_LEVELS.medium;
      } else if (dist < LOD_FAR) {
        targetN = LOD_LEVELS.far;
      } else {
        targetN = 0; // hidden
      }

      // Clamp to maxSubdivisions
      if (targetN > this.maxSubdivisions) {
        targetN = this.maxSubdivisions;
      }

      if (targetN !== this.faceLOD[faceId]) {
        this.rebuildFace(faceId, targetN);
        this.faceLOD[faceId] = targetN;
        changed = true;
      }
    }

    return changed;
  }

  /**
   * Rebuild geometry for a face at a given subdivision level.
   * If N=0, remove the mesh (hidden).
   */
  rebuildFace(faceId, N) {
    // Remove old mesh and grid lines
    if (this.faceMeshes[faceId]) {
      this.scene.remove(this.faceMeshes[faceId]);
      this.faceMeshes[faceId].geometry.dispose();
      this.faceMeshes[faceId].material.dispose();
      this.faceMeshes[faceId] = null;
    }
    if (this.faceGridLines[faceId]) {
      this.scene.remove(this.faceGridLines[faceId]);
      this.faceGridLines[faceId].geometry.dispose();
      this.faceGridLines[faceId].material.dispose();
      this.faceGridLines[faceId] = null;
    }
    this.faceColorArrays[faceId] = null;
    this.faceBaseColors[faceId] = null;

    if (N === 0) return;

    const { origin, e1, e2 } = this.faceEdges[faceId];

    // Compute per-tile terrain colors at this LOD's subdivision
    const tileColors = this.computeTileColors(faceId, N);
    this.faceBaseColors[faceId] = tileColors;

    // Generate (N+1)^2 vertices
    const positions = [];
    const uvs = [];
    const colors = [];

    for (let v = 0; v <= N; v++) {
      for (let u = 0; u <= N; u++) {
        const point = new THREE.Vector3()
          .copy(origin)
          .addScaledVector(e1, u / N)
          .addScaledVector(e2, v / N);
        point.normalize();

        positions.push(point.x, point.y, point.z);
        // v/N is flipped to 1-v/N to compensate for CanvasTexture flipY=true,
        // so that canvas row 0 (top) maps to vertex row 0 (low v).
        uvs.push(u / N, 1 - v / N);

        const color = this.vertexTerrainColor(v, u, N, tileColors);
        colors.push(color.r, color.g, color.b);
      }
    }

    // Generate triangle indices
    const indices = [];
    const p0 = new THREE.Vector3(positions[0], positions[1], positions[2]);
    const p1idx = (N + 1) * 3;
    const p1 = new THREE.Vector3(positions[p1idx], positions[p1idx + 1], positions[p1idx + 2]);
    const p2 = new THREE.Vector3(positions[3], positions[4], positions[5]);
    const edgeA = new THREE.Vector3().subVectors(p1, p0);
    const edgeB = new THREE.Vector3().subVectors(p2, p0);
    const testNormal = new THREE.Vector3().crossVectors(edgeA, edgeB);
    const needsFlip = testNormal.dot(p0) < 0;

    for (let v = 0; v < N; v++) {
      for (let u = 0; u < N; u++) {
        const tl = v * (N + 1) + u;
        const tr = v * (N + 1) + (u + 1);
        const bl = (v + 1) * (N + 1) + u;
        const br = (v + 1) * (N + 1) + (u + 1);
        if (needsFlip) {
          indices.push(tl, tr, bl);
          indices.push(tr, br, bl);
        } else {
          indices.push(tl, bl, tr);
          indices.push(tr, bl, br);
        }
      }
    }

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.Float32BufferAttribute(positions, 3));
    geometry.setAttribute("uv", new THREE.Float32BufferAttribute(uvs, 2));

    const colorAttr = new THREE.Float32BufferAttribute(colors, 3);
    geometry.setAttribute("color", colorAttr);
    geometry.setIndex(indices);
    geometry.computeVertexNormals();

    const material = new THREE.MeshLambertMaterial({
      vertexColors: true,
      side: THREE.FrontSide,
    });

    const mesh = new THREE.Mesh(geometry, material);
    this.scene.add(mesh);
    this.faceMeshes[faceId] = mesh;
    this.faceColorArrays[faceId] = colorAttr;

    // Grid lines
    const gridLines = this.buildGridLines(origin, e1, e2, N);
    this.scene.add(gridLines);
    this.faceGridLines[faceId] = gridLines;

    // Re-apply any active overlays for this face
    this.reapplyOverlays(faceId);
  }

  /**
   * Compute per-tile terrain colors for a face at a given subdivision N.
   * When N < maxSubdivisions, we sample the center of each LOD tile
   * from the full-resolution terrain data.
   */
  computeTileColors(faceId, N) {
    const fullN = this.maxSubdivisions;
    const faceTerrain = this.terrainData[faceId];
    const tileColors = [];

    for (let row = 0; row < N; row++) {
      for (let col = 0; col < N; col++) {
        // Map LOD tile to full-resolution tile (center sample)
        const fullRow = Math.floor(((row + 0.5) / N) * fullN);
        const fullCol = Math.floor(((col + 0.5) / N) * fullN);
        const clampRow = Math.min(fullRow, fullN - 1);
        const clampCol = Math.min(fullCol, fullN - 1);

        const td = faceTerrain[clampRow][clampCol];
        const baseColor = (this.terrainColors[td.t] || this.terrainColors.grassland).clone();
        if (td.r && this.resourceAccents[td.r]) {
          baseColor.lerp(this.resourceAccents[td.r], 0.55);
        }
        tileColors.push(baseColor);
      }
    }

    return tileColors;
  }

  /**
   * Compute vertex color by averaging adjacent tile colors.
   */
  vertexTerrainColor(v, u, N, tileColors) {
    const adjacent = [];
    for (let dv = -1; dv <= 0; dv++) {
      for (let du = -1; du <= 0; du++) {
        const row = v + dv;
        const col = u + du;
        if (row >= 0 && row < N && col >= 0 && col < N) {
          adjacent.push(tileColors[row * N + col]);
        }
      }
    }
    if (adjacent.length === 0) return new THREE.Color(0x4a7c3f);
    const result = new THREE.Color(0, 0, 0);
    for (const c of adjacent) {
      result.r += c.r;
      result.g += c.g;
      result.b += c.b;
    }
    result.r /= adjacent.length;
    result.g /= adjacent.length;
    result.b /= adjacent.length;
    return result;
  }

  buildGridLines(origin, e1, e2, N) {
    const linePositions = [];
    const LIFT = 1.001;

    for (let v = 0; v <= N; v++) {
      for (let u = 0; u < N; u++) {
        const p0 = new THREE.Vector3()
          .copy(origin)
          .addScaledVector(e1, u / N)
          .addScaledVector(e2, v / N)
          .normalize()
          .multiplyScalar(LIFT);
        const p1 = new THREE.Vector3()
          .copy(origin)
          .addScaledVector(e1, (u + 1) / N)
          .addScaledVector(e2, v / N)
          .normalize()
          .multiplyScalar(LIFT);
        linePositions.push(p0.x, p0.y, p0.z, p1.x, p1.y, p1.z);
      }
    }

    for (let u = 0; u <= N; u++) {
      for (let v = 0; v < N; v++) {
        const p0 = new THREE.Vector3()
          .copy(origin)
          .addScaledVector(e1, u / N)
          .addScaledVector(e2, v / N)
          .normalize()
          .multiplyScalar(LIFT);
        const p1 = new THREE.Vector3()
          .copy(origin)
          .addScaledVector(e1, u / N)
          .addScaledVector(e2, (v + 1) / N)
          .normalize()
          .multiplyScalar(LIFT);
        linePositions.push(p0.x, p0.y, p0.z, p1.x, p1.y, p1.z);
      }
    }

    const lineGeo = new THREE.BufferGeometry();
    lineGeo.setAttribute("position", new THREE.Float32BufferAttribute(linePositions, 3));
    const lineMat = new THREE.LineBasicMaterial({
      color: 0x000000,
      opacity: 0.15,
      transparent: true,
    });
    return new THREE.LineSegments(lineGeo, lineMat);
  }

  /**
   * Get the tile center position on the sphere for a given face at its current LOD.
   * Maps full-resolution (row, col) to the LOD-appropriate position.
   */
  getTileCenter(faceId, row, col) {
    const N = this.maxSubdivisions;
    const { origin, e1, e2 } = this.faceEdges[faceId];
    const center = new THREE.Vector3()
      .copy(origin)
      .addScaledVector(e1, (col + 0.5) / N)
      .addScaledVector(e2, (row + 0.5) / N);
    center.normalize();
    return center;
  }

  /**
   * Get the meshes array for raycasting. Only includes non-null meshes.
   */
  getRaycastMeshes() {
    return this.faceMeshes.filter((m) => m !== null);
  }

  /**
   * Given a raycast hit, determine the face ID, row, and col.
   * Returns {face, row, col} or null.
   */
  hitToTile(hit) {
    const faceId = this.faceMeshes.indexOf(hit.object);
    if (faceId === -1) return null;

    const N = this.faceLOD[faceId];
    if (N === 0) return null;

    const cellIndex = Math.floor(hit.faceIndex / 2);
    const lodRow = Math.floor(cellIndex / N);
    const lodCol = cellIndex % N;

    // Map LOD tile back to full-resolution coordinates
    const fullN = this.maxSubdivisions;
    const fullRow = Math.floor(((lodRow + 0.5) / N) * fullN);
    const fullCol = Math.floor(((lodCol + 0.5) / N) * fullN);

    return {
      face: faceId,
      row: Math.min(fullRow, fullN - 1),
      col: Math.min(fullCol, fullN - 1),
    };
  }

  /**
   * Set an overlay on a tile (selected, hover, error, or null).
   * Maps full-resolution coords to current LOD coords.
   */
  setTileOverlay(faceId, row, col, overlay) {
    const N = this.faceLOD[faceId];
    const fullN = this.maxSubdivisions;

    // Store at full-resolution key for persistence across LOD changes
    const fullKey = row * fullN + col;
    if (overlay) {
      this.faceOverlays[faceId].set(fullKey, overlay);
    } else {
      this.faceOverlays[faceId].delete(fullKey);
    }

    if (N === 0) return; // face not visible

    // Map to LOD tile
    const lodRow = Math.floor((row / fullN) * N);
    const lodCol = Math.floor((col / fullN) * N);
    this.refreshTileVertices(faceId, lodRow, lodCol, N);
  }

  getTileOverlay(faceId, row, col) {
    const fullN = this.maxSubdivisions;
    return this.faceOverlays[faceId].get(row * fullN + col) || null;
  }

  /**
   * Re-apply all stored overlays after an LOD change.
   */
  reapplyOverlays(faceId) {
    const N = this.faceLOD[faceId];
    if (N === 0) return;

    const fullN = this.maxSubdivisions;
    const refreshedLodTiles = new Set();

    for (const [fullKey] of this.faceOverlays[faceId]) {
      const fullRow = Math.floor(fullKey / fullN);
      const fullCol = fullKey % fullN;
      const lodRow = Math.floor((fullRow / fullN) * N);
      const lodCol = Math.floor((fullCol / fullN) * N);
      const lodKey = lodRow * N + lodCol;

      if (!refreshedLodTiles.has(lodKey)) {
        refreshedLodTiles.add(lodKey);
        this.refreshTileVertices(faceId, lodRow, lodCol, N);
      }
    }
  }

  /**
   * Refresh the 4 corner vertices of a LOD tile, with overlay blending.
   */
  refreshTileVertices(faceId, lodRow, lodCol, N) {
    const colorAttr = this.faceColorArrays[faceId];
    if (!colorAttr) return;

    const arr = colorAttr.array;

    for (let dv = 0; dv <= 1; dv++) {
      for (let du = 0; du <= 1; du++) {
        const v = lodRow + dv;
        const u = lodCol + du;
        const vi = v * (N + 1) + u;
        const color = this.computeVertexColor(faceId, v, u, N);
        arr[vi * 3] = color.r;
        arr[vi * 3 + 1] = color.g;
        arr[vi * 3 + 2] = color.b;
      }
    }

    colorAttr.needsUpdate = true;
  }

  /**
   * Compute a vertex color considering overlays. Blends adjacent tiles' effective colors.
   */
  computeVertexColor(faceId, v, u, N) {
    const tileColors = this.faceBaseColors[faceId];
    if (!tileColors) return new THREE.Color(0x4a7c3f);

    const fullN = this.maxSubdivisions;
    const overlays = this.faceOverlays[faceId];
    const adjacent = [];

    for (let dv = -1; dv <= 0; dv++) {
      for (let du = -1; du <= 0; du++) {
        const row = v + dv;
        const col = u + du;
        if (row >= 0 && row < N && col >= 0 && col < N) {
          const base = tileColors[row * N + col];

          // Check if any full-resolution tile in this LOD tile has an overlay
          const overlay = this.lodTileOverlay(faceId, row, col, N, fullN, overlays);
          adjacent.push(this.applyOverlay(base, overlay));
        }
      }
    }

    if (adjacent.length === 0) return new THREE.Color(0x4a7c3f);

    const result = new THREE.Color(0, 0, 0);
    for (const c of adjacent) {
      result.r += c.r;
      result.g += c.g;
      result.b += c.b;
    }
    result.r /= adjacent.length;
    result.g /= adjacent.length;
    result.b /= adjacent.length;
    return result;
  }

  /**
   * Find the strongest overlay for a LOD tile (which may cover multiple full-res tiles).
   */
  lodTileOverlay(faceId, lodRow, lodCol, N, fullN, overlays) {
    if (overlays.size === 0) return null;

    // Range of full-res tiles covered by this LOD tile
    const startRow = Math.floor((lodRow / N) * fullN);
    const endRow = Math.floor(((lodRow + 1) / N) * fullN);
    const startCol = Math.floor((lodCol / N) * fullN);
    const endCol = Math.floor(((lodCol + 1) / N) * fullN);

    // Priority: error > selected > hover
    let best = null;
    const priority = { error: 3, selected: 2, hover: 1 };

    for (let r = startRow; r < endRow && r < fullN; r++) {
      for (let c = startCol; c < endCol && c < fullN; c++) {
        const ov = overlays.get(r * fullN + c);
        if (ov && (!best || (priority[ov] || 0) > (priority[best] || 0))) {
          best = ov;
        }
      }
    }

    return best;
  }

  // Overlay color constants
  static HIGHLIGHT_TINT = new THREE.Color(0xffdd44);
  static HOVER_TINT = new THREE.Color(0xaaddff);
  static ERROR_TINT = new THREE.Color(0xff2222);
  static HIGHLIGHT_BLEND = 0.55;
  static HOVER_BLEND = 0.35;

  applyOverlay(baseColor, overlay) {
    if (!overlay) return baseColor;
    const result = baseColor.clone();
    if (overlay === "selected") {
      result.lerp(ChunkManager.HIGHLIGHT_TINT, ChunkManager.HIGHLIGHT_BLEND);
    } else if (overlay === "hover") {
      result.lerp(ChunkManager.HOVER_TINT, ChunkManager.HOVER_BLEND);
    } else if (overlay === "error") {
      result.lerp(ChunkManager.ERROR_TINT, 0.6);
    }
    return result;
  }

  /**
   * Get the current LOD for a face (0 = hidden).
   */
  getFaceLOD(faceId) {
    return this.faceLOD[faceId];
  }

  /**
   * Dispose all GPU resources.
   */
  dispose() {
    for (let i = 0; i < this.faceMeshes.length; i++) {
      if (this.faceMeshes[i]) {
        this.scene.remove(this.faceMeshes[i]);
        this.faceMeshes[i].geometry.dispose();
        this.faceMeshes[i].material.dispose();
      }
      if (this.faceGridLines[i]) {
        this.scene.remove(this.faceGridLines[i]);
        this.faceGridLines[i].geometry.dispose();
        this.faceGridLines[i].material.dispose();
      }
    }
  }
}
