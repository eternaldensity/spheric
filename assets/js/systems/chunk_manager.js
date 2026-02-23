import * as THREE from "three";

/**
 * ChunkManager handles LOD (Level of Detail) for each cell of the sphere.
 *
 * Each face is divided into a 4×4 grid of "cells". Each cell is independently
 * managed for LOD based on camera distance to the cell center:
 * - Close:     full 16×16 subdivision within the cell
 * - Medium:    8×8
 * - Far:       4×4
 * - Ultra-far: 2×2
 * - Hidden:    unloaded (0)
 *
 * Hemisphere culling hides cells occluded by the sphere.  Thresholds scale
 * with zoom distance so distant views are cheaper.  LOD transitions are
 * throttled and meshes are cached to avoid frame stutters.
 *
 * Cell key: faceId * 16 + cellRow * 4 + cellCol
 */

// LOD base thresholds (camera distance to cell center on unit sphere).
// Scaled at runtime by zoom distance for more aggressive culling when far out.
const BASE_CLOSE = 1.4;
const BASE_MEDIUM = 2.0;
const BASE_FAR = 3.0;
const BASE_ULTRA_FAR = 4.0;

// Hemisphere culling margin — small buffer past the geometric horizon so
// cells don't pop in/out right at the planet limb.
const HORIZON_MARGIN = 0.05;

const TILES_PER_CELL = 16;

// Maximum non-hide LOD transitions per frame to prevent stutter during
// fast zooming.  Hide transitions (N→0) are always immediate since they
// are cheap visibility toggles.
const MAX_LOD_CHANGES_PER_FRAME = 8;

// Reusable vector to avoid allocations in the hot update() loop
const _camNorm = new THREE.Vector3();

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

    // Mesh cache: cellKey -> Map<N, { mesh, gridLines }>
    // Cached meshes are kept hidden in the scene so LOD switches just
    // toggle visibility instead of allocating/disposing GPU resources.
    this.meshCache = new Map();

    // Shared materials to avoid per-cell allocation
    this.sharedGridMaterial = new THREE.LineBasicMaterial({
      color: 0x000000,
      opacity: 0.15,
      transparent: true,
    });

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
   * Compute the desired LOD subdivision level for a cell.
   * Thresholds tighten as the camera zooms out so distant views are cheaper.
   */
  computeLODLevel(cellDist, camDist) {
    // Zoom scale: at camDist 1.08 → 1.0, at camDist 8.0 → ~0.58
    const scale = Math.max(0.5, 1.0 - 0.06 * Math.max(0, camDist - 1.0));
    if (cellDist < BASE_CLOSE * scale) return 16;
    if (cellDist < BASE_MEDIUM * scale) return 8;
    if (cellDist < BASE_FAR * scale) return 4;
    if (cellDist < BASE_ULTRA_FAR * scale) return 2;
    return 0;
  }

  /**
   * Update LOD levels based on camera position.
   * Uses hemisphere culling (dot-product backface test) and zoom-aware
   * distance thresholds.  Returns array of { faceId, cellRow, cellCol }
   * that changed LOD.
   * @param {THREE.Vector3} cameraPos
   */
  update(cameraPos) {
    const changed = [];
    const pending = []; // non-hide transitions to throttle
    const camDist = cameraPos.length();
    const camNorm = _camNorm.copy(cameraPos).normalize();
    // Geometric horizon: surface point visible when dot(camNorm, point) >= 1/d
    const horizonDot = 1.0 / camDist - HORIZON_MARGIN;

    for (let faceId = 0; faceId < this.faceIndices.length; faceId++) {
      // Face-level hemisphere cull: if face center is behind the horizon,
      // the entire face is occluded by the sphere.
      const faceDot = this.faceCenters[faceId].dot(camNorm);
      if (faceDot < horizonDot) {
        for (let cr = 0; cr < this.cellsPerAxis; cr++) {
          for (let cc = 0; cc < this.cellsPerAxis; cc++) {
            const key = this.cellKey(faceId, cr, cc);
            if (this.cellLOD.get(key) !== 0) {
              // Hiding is cheap (visibility toggle), apply immediately
              this.rebuildCell(faceId, cr, cc, 0);
              this.cellLOD.set(key, 0);
              changed.push({ faceId, cellRow: cr, cellCol: cc });
            }
          }
        }
        continue;
      }

      // Per-cell LOD with per-cell backface test
      for (let cr = 0; cr < this.cellsPerAxis; cr++) {
        for (let cc = 0; cc < this.cellsPerAxis; cc++) {
          const key = this.cellKey(faceId, cr, cc);
          const cellCenter = this.cellCenters.get(key);

          let targetN;
          if (cellCenter.dot(camNorm) < horizonDot) {
            targetN = 0;
          } else {
            const dist = cameraPos.distanceTo(cellCenter);
            targetN = this.computeLODLevel(dist, camDist);
          }

          const currentN = this.cellLOD.get(key);
          if (targetN === currentN) continue;

          if (targetN === 0) {
            // Hiding is cheap, apply immediately
            this.rebuildCell(faceId, cr, cc, 0);
            this.cellLOD.set(key, 0);
            changed.push({ faceId, cellRow: cr, cellCol: cc });
          } else {
            // Queue non-hide transitions for throttling
            const dist = cameraPos.distanceTo(cellCenter);
            pending.push({ faceId, cr, cc, key, targetN, dist });
          }
        }
      }
    }

    // Throttle: apply up to MAX_LOD_CHANGES visible transitions per frame,
    // prioritising closest cells first.
    if (pending.length > 0) {
      pending.sort((a, b) => a.dist - b.dist);
      const limit = Math.min(pending.length, MAX_LOD_CHANGES_PER_FRAME);
      for (let i = 0; i < limit; i++) {
        const { faceId, cr, cc, key, targetN } = pending[i];
        this.rebuildCell(faceId, cr, cc, targetN);
        this.cellLOD.set(key, targetN);
        changed.push({ faceId, cellRow: cr, cellCol: cc });
      }
    }

    return changed;
  }

  /**
   * Rebuild (or show cached) geometry for a cell at a given subdivision level.
   * If N=0, hide the mesh.  Cached meshes are kept hidden in the scene so
   * LOD switches toggle visibility instead of allocating GPU resources.
   */
  rebuildCell(faceId, cellRow, cellCol, N) {
    const key = this.cellKey(faceId, cellRow, cellCol);

    // --- Hide the currently-active mesh for this cell ---
    const oldMesh = this.cellMeshes.get(key);
    if (oldMesh) {
      oldMesh.visible = false;
      this.meshToCellInfo.delete(oldMesh);
      this.cellMeshes.delete(key);
    }

    const oldLines = this.cellGridLines.get(key);
    if (oldLines) {
      oldLines.visible = false;
      this.cellGridLines.delete(key);
    }

    this.cellColorArrays.delete(key);
    this.cellBaseColors.delete(key);

    if (N === 0) return;

    // Guard: terrain data must be loaded for this face
    if (!this.terrainData[faceId]) return;

    // Compute per-tile terrain colors at this LOD
    const tileColors = this.computeCellTileColors(faceId, cellRow, cellCol, N);
    this.cellBaseColors.set(key, tileColors);

    // --- Check mesh cache ---
    let cellCache = this.meshCache.get(key);
    if (!cellCache) {
      cellCache = new Map();
      this.meshCache.set(key, cellCache);
    }

    const cached = cellCache.get(N);
    if (cached) {
      // Reuse cached mesh — update vertex colors and show it
      const mesh = cached.mesh;
      this.updateVertexColors(mesh.geometry, N, tileColors);

      mesh.visible = true;
      this.cellMeshes.set(key, mesh);
      const colorAttr = mesh.geometry.getAttribute("color");
      this.cellColorArrays.set(key, colorAttr);
      this.meshToCellInfo.set(mesh, { faceId, cellRow, cellCol });

      if (cached.gridLines) {
        cached.gridLines.visible = true;
        this.cellGridLines.set(key, cached.gridLines);
      }

      this.reapplyOverlays(faceId, cellRow, cellCol);
      colorAttr.needsUpdate = true;
      return;
    }

    // --- Build new geometry from scratch ---
    const { origin, e1, e2 } = this.cellEdges.get(key);

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

    // Grid lines — only at medium detail or higher
    let gridLines = null;
    if (N >= 8) {
      gridLines = this.buildGridLines(origin, e1, e2, N);
      this.scene.add(gridLines);
      this.cellGridLines.set(key, gridLines);
    }

    // Store in cache for future LOD revisits
    cellCache.set(N, { mesh, gridLines });

    // Re-apply any active overlays for this cell
    this.reapplyOverlays(faceId, cellRow, cellCol);

    // Safety: ensure vertex colors are flagged for GPU upload after overlays
    colorAttr.needsUpdate = true;
  }

  /**
   * Update vertex colors on a cached geometry from fresh tile colors.
   */
  updateVertexColors(geometry, N, tileColors) {
    const colorAttr = geometry.getAttribute("color");
    const arr = colorAttr.array;

    for (let v = 0; v <= N; v++) {
      for (let u = 0; u <= N; u++) {
        const vi = v * (N + 1) + u;
        const color = this.vertexTerrainColor(v, u, N, tileColors);
        arr[vi * 3] = color.r;
        arr[vi * 3 + 1] = color.g;
        arr[vi * 3 + 2] = color.b;
      }
    }

    colorAttr.needsUpdate = true;
  }

  /**
   * Evict cached meshes for every cell on a face.  Called when terrain data
   * arrives so stale-color caches at other LOD levels are discarded.
   * The currently-active LOD mesh is kept (it will be refreshed by rebuildCell).
   */
  clearFaceCache(faceId) {
    for (let cr = 0; cr < this.cellsPerAxis; cr++) {
      for (let cc = 0; cc < this.cellsPerAxis; cc++) {
        const key = this.cellKey(faceId, cr, cc);
        const cellCache = this.meshCache.get(key);
        if (!cellCache) continue;
        const activeN = this.cellLOD.get(key) || 0;
        for (const [n, entry] of cellCache) {
          if (n === activeN) continue; // keep the one rebuildCell will refresh
          this.scene.remove(entry.mesh);
          entry.mesh.geometry.dispose();
          entry.mesh.material.dispose();
          if (entry.gridLines) {
            this.scene.remove(entry.gridLines);
            entry.gridLines.geometry.dispose();
          }
          cellCache.delete(n);
        }
      }
    }
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
    return new THREE.LineSegments(lineGeo, this.sharedGridMaterial);
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
   * Check if a tile's cell is currently visible (LOD > 0).
   */
  isTileVisible(faceId, row, col) {
    const cellRow = Math.floor(row / TILES_PER_CELL);
    const cellCol = Math.floor(col / TILES_PER_CELL);
    return (this.cellLOD.get(this.cellKey(faceId, cellRow, cellCol)) || 0) > 0;
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
          if (!base) continue;
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
   * Dispose all GPU resources including the mesh cache.
   */
  dispose() {
    // Dispose every cached mesh (active or hidden)
    for (const [, cellCache] of this.meshCache) {
      for (const [, entry] of cellCache) {
        this.scene.remove(entry.mesh);
        entry.mesh.geometry.dispose();
        entry.mesh.material.dispose();
        if (entry.gridLines) {
          this.scene.remove(entry.gridLines);
          entry.gridLines.geometry.dispose();
        }
      }
    }
    this.meshCache.clear();
    this.sharedGridMaterial.dispose();
    this.cellMeshes.clear();
    this.cellGridLines.clear();
    this.cellColorArrays.clear();
    this.cellBaseColors.clear();
    this.meshToCellInfo.clear();
  }
}
