import * as THREE from "three";

/**
 * ChunkManager handles LOD (Level of Detail) for each cell of the sphere.
 *
 * Each face is divided into a 4×4 grid of "cells". Each cell is independently
 * managed for LOD based on camera distance to the cell center:
 * - Close:  full 16×16 subdivision within the cell
 * - Medium: 8×8
 * - Far:    4×4
 * - Hidden: unloaded (0)
 *
 * Cell key: faceId * 16 + cellRow * 4 + cellCol
 */

// LOD thresholds (camera distance to cell center on unit sphere)
const LOD_CLOSE = 1.6;
const LOD_MEDIUM = 2.5;
const LOD_FAR = 4.0;

// Face-level cull threshold: if camera is farther than this from face center,
// skip all 16 cells on that face
const FACE_CULL_DIST = LOD_FAR + 1.5;

const TILES_PER_CELL = 16;

export class ChunkManager {
  /**
   * @param {THREE.Scene} scene
   * @param {Array<THREE.Vector3>} baseVertices - 32 base polyhedron vertices
   * @param {Array<Array<number>>} faceIndices - 30 faces, each [a,b,c,d]
   * @param {number} maxSubdivisions - the full resolution subdivision count (e.g. 64)
   * @param {object} colorConfig - { terrainColors, resourceAccents }
   */
  constructor(scene, baseVertices, faceIndices, maxSubdivisions, colorConfig) {
    this.scene = scene;
    this.baseVertices = baseVertices;
    this.faceIndices = faceIndices;
    this.maxSubdivisions = maxSubdivisions;
    this.terrainColors = colorConfig.terrainColors;
    this.resourceAccents = colorConfig.resourceAccents;
    this.cellsPerAxis = 4;

    // Terrain data: populated asynchronously via terrain_face events
    // terrainData[faceId] = array[64][64] of {t, r} or null if not yet loaded
    this.terrainData = [];
    for (let i = 0; i < faceIndices.length; i++) {
      this.terrainData.push(null);
    }

    // Per-face precomputed data
    this.faceEdges = [];    // { origin, e1, e2 } per face
    this.faceCenters = [];  // THREE.Vector3 per face (normalized)

    // Per-cell state (keyed by cellKey)
    this.cellMeshes = new Map();
    this.cellGridLines = new Map();
    this.cellLOD = new Map();
    this.cellColorArrays = new Map();
    this.cellBaseColors = new Map();
    this.cellOverlays = new Map();
    this.cellEdges = new Map();
    this.cellCenters = new Map();

    // Reverse lookup: mesh -> { faceId, cellRow, cellCol }
    this.meshToCellInfo = new Map();

    // Precompute face and cell geometry
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

      // Precompute cell edges and centers
      for (let cr = 0; cr < this.cellsPerAxis; cr++) {
        for (let cc = 0; cc < this.cellsPerAxis; cc++) {
          const key = this.cellKey(faceId, cr, cc);

          // Cell origin = face_origin + (cc/4)*e1 + (cr/4)*e2
          const cellOrigin = A.clone()
            .addScaledVector(e1, cc / this.cellsPerAxis)
            .addScaledVector(e2, cr / this.cellsPerAxis);

          const cellE1 = e1.clone().multiplyScalar(1 / this.cellsPerAxis);
          const cellE2 = e2.clone().multiplyScalar(1 / this.cellsPerAxis);

          this.cellEdges.set(key, { origin: cellOrigin, e1: cellE1, e2: cellE2 });

          // Cell center (normalized to sphere surface)
          const cellCenter = A.clone()
            .addScaledVector(e1, (cc + 0.5) / this.cellsPerAxis)
            .addScaledVector(e2, (cr + 0.5) / this.cellsPerAxis)
            .normalize();
          this.cellCenters.set(key, cellCenter);

          this.cellLOD.set(key, 0);
          this.cellOverlays.set(key, new Map());
        }
      }
    }
  }

  /**
   * Compute a unique key for a cell.
   */
  cellKey(faceId, cellRow, cellCol) {
    return faceId * 16 + cellRow * 4 + cellCol;
  }

  /**
   * Convert face-global row/col (0-63) to cell coordinates.
   */
  toCellCoords(row, col) {
    return {
      cellRow: Math.floor(row / TILES_PER_CELL),
      cellCol: Math.floor(col / TILES_PER_CELL),
      localRow: row % TILES_PER_CELL,
      localCol: col % TILES_PER_CELL,
    };
  }

  /**
   * Update LOD levels based on camera position.
   * Returns array of { faceId, cellRow, cellCol } that changed LOD.
   * @param {THREE.Vector3} cameraPos
   */
  update(cameraPos) {
    const changed = [];

    for (let faceId = 0; faceId < this.faceIndices.length; faceId++) {
      const faceDist = cameraPos.distanceTo(this.faceCenters[faceId]);

      // Face-level pre-cull: if entire face is far away, hide all cells
      if (faceDist > FACE_CULL_DIST) {
        for (let cr = 0; cr < this.cellsPerAxis; cr++) {
          for (let cc = 0; cc < this.cellsPerAxis; cc++) {
            const key = this.cellKey(faceId, cr, cc);
            if (this.cellLOD.get(key) !== 0) {
              this.rebuildCell(faceId, cr, cc, 0);
              this.cellLOD.set(key, 0);
              changed.push({ faceId, cellRow: cr, cellCol: cc });
            }
          }
        }
        continue;
      }

      // Per-cell LOD
      for (let cr = 0; cr < this.cellsPerAxis; cr++) {
        for (let cc = 0; cc < this.cellsPerAxis; cc++) {
          const key = this.cellKey(faceId, cr, cc);
          const dist = cameraPos.distanceTo(this.cellCenters.get(key));

          let targetN;
          if (dist < LOD_CLOSE) targetN = 16;
          else if (dist < LOD_MEDIUM) targetN = 8;
          else if (dist < LOD_FAR) targetN = 4;
          else targetN = 0;

          if (targetN !== this.cellLOD.get(key)) {
            this.rebuildCell(faceId, cr, cc, targetN);
            this.cellLOD.set(key, targetN);
            changed.push({ faceId, cellRow: cr, cellCol: cc });
          }
        }
      }
    }

    return changed;
  }

  /**
   * Rebuild geometry for a cell at a given subdivision level.
   * If N=0, remove the mesh (hidden).
   */
  rebuildCell(faceId, cellRow, cellCol, N) {
    const key = this.cellKey(faceId, cellRow, cellCol);

    // Remove old mesh and grid lines
    const oldMesh = this.cellMeshes.get(key);
    if (oldMesh) {
      this.scene.remove(oldMesh);
      oldMesh.geometry.dispose();
      oldMesh.material.dispose();
      this.meshToCellInfo.delete(oldMesh);
      this.cellMeshes.delete(key);
    }

    const oldLines = this.cellGridLines.get(key);
    if (oldLines) {
      this.scene.remove(oldLines);
      oldLines.geometry.dispose();
      oldLines.material.dispose();
      this.cellGridLines.delete(key);
    }

    this.cellColorArrays.delete(key);
    this.cellBaseColors.delete(key);

    if (N === 0) return;

    // Guard: terrain data must be loaded for this face
    if (!this.terrainData[faceId]) return;

    const { origin, e1, e2 } = this.cellEdges.get(key);

    // Compute per-tile terrain colors at this LOD
    const tileColors = this.computeCellTileColors(faceId, cellRow, cellCol, N);
    this.cellBaseColors.set(key, tileColors);

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
        uvs.push(u / N, 1 - v / N);

        const color = this.vertexTerrainColor(v, u, N, tileColors);
        colors.push(color.r, color.g, color.b);
      }
    }

    // Generate triangle indices (determine winding)
    const p0 = new THREE.Vector3(positions[0], positions[1], positions[2]);
    const p1idx = (N + 1) * 3;
    const p1 = new THREE.Vector3(positions[p1idx], positions[p1idx + 1], positions[p1idx + 2]);
    const p2 = new THREE.Vector3(positions[3], positions[4], positions[5]);
    const edgeA = new THREE.Vector3().subVectors(p1, p0);
    const edgeB = new THREE.Vector3().subVectors(p2, p0);
    const testNormal = new THREE.Vector3().crossVectors(edgeA, edgeB);
    const needsFlip = testNormal.dot(p0) < 0;

    const indices = [];
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
    this.cellMeshes.set(key, mesh);
    this.cellColorArrays.set(key, colorAttr);
    this.meshToCellInfo.set(mesh, { faceId, cellRow, cellCol });

    // Grid lines
    const gridLines = this.buildGridLines(origin, e1, e2, N);
    this.scene.add(gridLines);
    this.cellGridLines.set(key, gridLines);

    // Re-apply any active overlays for this cell
    this.reapplyOverlays(faceId, cellRow, cellCol);
  }

  /**
   * Compute per-tile terrain colors for a cell at a given LOD N.
   * Maps LOD tiles to face-global full-resolution terrain data.
   */
  computeCellTileColors(faceId, cellRow, cellCol, N) {
    const faceTerrain = this.terrainData[faceId];
    if (!faceTerrain) return [];

    const tileColors = [];

    for (let row = 0; row < N; row++) {
      for (let col = 0; col < N; col++) {
        // Map cell-local LOD tile to full-res tile within the cell
        const localFullRow = Math.min(
          Math.floor(((row + 0.5) / N) * TILES_PER_CELL),
          TILES_PER_CELL - 1
        );
        const localFullCol = Math.min(
          Math.floor(((col + 0.5) / N) * TILES_PER_CELL),
          TILES_PER_CELL - 1
        );

        // Convert to face-global coordinates
        const faceRow = cellRow * TILES_PER_CELL + localFullRow;
        const faceCol = cellCol * TILES_PER_CELL + localFullCol;

        const td = faceTerrain[faceRow][faceCol];
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
   * Get the tile center position on the sphere for a given face at full resolution.
   * Uses face-level edge vectors with maxSubdivisions (64).
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
   * Get all visible meshes for raycasting.
   */
  getRaycastMeshes() {
    return Array.from(this.cellMeshes.values());
  }

  /**
   * Given a raycast hit, determine the face ID, row, and col.
   * Returns {face, row, col} or null.
   */
  hitToTile(hit) {
    const cellInfo = this.meshToCellInfo.get(hit.object);
    if (!cellInfo) return null;

    const { faceId, cellRow, cellCol } = cellInfo;
    const key = this.cellKey(faceId, cellRow, cellCol);
    const N = this.cellLOD.get(key);
    if (N === 0) return null;

    // Determine which tile within the cell mesh was hit
    const cellIndex = Math.floor(hit.faceIndex / 2);
    const lodRow = Math.floor(cellIndex / N);
    const lodCol = cellIndex % N;

    // Map LOD tile to full-res coordinates within the cell
    const localRow = Math.min(
      Math.floor(((lodRow + 0.5) / N) * TILES_PER_CELL),
      TILES_PER_CELL - 1
    );
    const localCol = Math.min(
      Math.floor(((lodCol + 0.5) / N) * TILES_PER_CELL),
      TILES_PER_CELL - 1
    );

    // Convert to face-global coordinates
    const fullRow = cellRow * TILES_PER_CELL + localRow;
    const fullCol = cellCol * TILES_PER_CELL + localCol;

    return {
      face: faceId,
      row: Math.min(fullRow, this.maxSubdivisions - 1),
      col: Math.min(fullCol, this.maxSubdivisions - 1),
    };
  }

  /**
   * Set an overlay on a tile (selected, hover, error, or null).
   * Maps full-resolution coords to the correct cell.
   */
  setTileOverlay(faceId, row, col, overlay) {
    const { cellRow, cellCol, localRow, localCol } = this.toCellCoords(row, col);
    const key = this.cellKey(faceId, cellRow, cellCol);
    const N = this.cellLOD.get(key);

    // Store at full-resolution key for persistence across LOD changes
    const fullKey = row * this.maxSubdivisions + col;
    const overlayMap = this.cellOverlays.get(key);
    if (overlayMap) {
      if (overlay) {
        overlayMap.set(fullKey, overlay);
      } else {
        overlayMap.delete(fullKey);
      }
    }

    if (!N || N === 0) return;

    // Map to LOD tile within cell
    const lodRow = Math.floor((localRow / TILES_PER_CELL) * N);
    const lodCol = Math.floor((localCol / TILES_PER_CELL) * N);
    this.refreshTileVertices(key, lodRow, lodCol, N);
  }

  getTileOverlay(faceId, row, col) {
    const { cellRow, cellCol } = this.toCellCoords(row, col);
    const key = this.cellKey(faceId, cellRow, cellCol);
    const overlayMap = this.cellOverlays.get(key);
    if (!overlayMap) return null;
    return overlayMap.get(row * this.maxSubdivisions + col) || null;
  }

  /**
   * Get the current LOD for a cell.
   */
  getCellLOD(faceId, cellRow, cellCol) {
    return this.cellLOD.get(this.cellKey(faceId, cellRow, cellCol)) || 0;
  }

  /**
   * Re-apply all stored overlays after an LOD change for a specific cell.
   */
  reapplyOverlays(faceId, cellRow, cellCol) {
    const key = this.cellKey(faceId, cellRow, cellCol);
    const N = this.cellLOD.get(key);
    if (!N || N === 0) return;

    const overlayMap = this.cellOverlays.get(key);
    if (!overlayMap || overlayMap.size === 0) return;

    const refreshedLodTiles = new Set();

    for (const [fullKey] of overlayMap) {
      const fullRow = Math.floor(fullKey / this.maxSubdivisions);
      const fullCol = fullKey % this.maxSubdivisions;
      const localRow = fullRow - cellRow * TILES_PER_CELL;
      const localCol = fullCol - cellCol * TILES_PER_CELL;
      const lodRow = Math.floor((localRow / TILES_PER_CELL) * N);
      const lodCol = Math.floor((localCol / TILES_PER_CELL) * N);
      const lodKey = lodRow * N + lodCol;

      if (!refreshedLodTiles.has(lodKey)) {
        refreshedLodTiles.add(lodKey);
        this.refreshTileVertices(key, lodRow, lodCol, N);
      }
    }
  }

  /**
   * Refresh the 4 corner vertices of a LOD tile, with overlay blending.
   */
  refreshTileVertices(cellKey, lodRow, lodCol, N) {
    const colorAttr = this.cellColorArrays.get(cellKey);
    if (!colorAttr) return;

    const arr = colorAttr.array;

    for (let dv = 0; dv <= 1; dv++) {
      for (let du = 0; du <= 1; du++) {
        const v = lodRow + dv;
        const u = lodCol + du;
        const vi = v * (N + 1) + u;
        const color = this.computeVertexColor(cellKey, v, u, N);
        arr[vi * 3] = color.r;
        arr[vi * 3 + 1] = color.g;
        arr[vi * 3 + 2] = color.b;
      }
    }

    colorAttr.needsUpdate = true;
  }

  /**
   * Compute a vertex color considering overlays.
   */
  computeVertexColor(cellKey, v, u, N) {
    const tileColors = this.cellBaseColors.get(cellKey);
    if (!tileColors) return new THREE.Color(0x4a7c3f);

    const overlays = this.cellOverlays.get(cellKey);
    const adjacent = [];

    for (let dv = -1; dv <= 0; dv++) {
      for (let du = -1; du <= 0; du++) {
        const row = v + dv;
        const col = u + du;
        if (row >= 0 && row < N && col >= 0 && col < N) {
          const base = tileColors[row * N + col];
          const overlay = this.lodTileOverlay(cellKey, row, col, N, overlays);
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
   * Find the strongest overlay for a LOD tile within a cell.
   */
  lodTileOverlay(cellKey, lodRow, lodCol, N, overlays) {
    if (!overlays || overlays.size === 0) return null;

    // Decode cell from key
    const faceId = Math.floor(cellKey / 16);
    const rem = cellKey % 16;
    const cellRow = Math.floor(rem / 4);
    const cellCol = rem % 4;

    // Range of full-res tiles covered by this LOD tile
    const startLocalRow = Math.floor((lodRow / N) * TILES_PER_CELL);
    const endLocalRow = Math.floor(((lodRow + 1) / N) * TILES_PER_CELL);
    const startLocalCol = Math.floor((lodCol / N) * TILES_PER_CELL);
    const endLocalCol = Math.floor(((lodCol + 1) / N) * TILES_PER_CELL);

    const priority = { error: 3, selected: 2, hover: 1 };
    let best = null;

    for (let lr = startLocalRow; lr < endLocalRow && lr < TILES_PER_CELL; lr++) {
      for (let lc = startLocalCol; lc < endLocalCol && lc < TILES_PER_CELL; lc++) {
        const faceRow = cellRow * TILES_PER_CELL + lr;
        const faceCol = cellCol * TILES_PER_CELL + lc;
        const fullKey = faceRow * this.maxSubdivisions + faceCol;
        const ov = overlays.get(fullKey);
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
  static DEMOLISH_TINT = new THREE.Color(0xff4444);
  static HIGHLIGHT_BLEND = 0.55;
  static HOVER_BLEND = 0.35;
  static DEMOLISH_BLEND = 0.5;

  applyOverlay(baseColor, overlay) {
    if (!overlay) return baseColor;
    const result = baseColor.clone();
    if (overlay === "selected") {
      result.lerp(ChunkManager.HIGHLIGHT_TINT, ChunkManager.HIGHLIGHT_BLEND);
    } else if (overlay === "hover") {
      result.lerp(ChunkManager.HOVER_TINT, ChunkManager.HOVER_BLEND);
    } else if (overlay === "error") {
      result.lerp(ChunkManager.ERROR_TINT, 0.6);
    } else if (overlay === "demolish") {
      result.lerp(ChunkManager.DEMOLISH_TINT, ChunkManager.DEMOLISH_BLEND);
    }
    return result;
  }

  /**
   * Dispose all GPU resources.
   */
  dispose() {
    for (const [, mesh] of this.cellMeshes) {
      this.scene.remove(mesh);
      mesh.geometry.dispose();
      mesh.material.dispose();
    }
    for (const [, lines] of this.cellGridLines) {
      this.scene.remove(lines);
      lines.geometry.dispose();
      lines.material.dispose();
    }
    this.cellMeshes.clear();
    this.cellGridLines.clear();
    this.meshToCellInfo.clear();
  }
}
