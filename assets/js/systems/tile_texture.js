import * as THREE from "three";

/**
 * TileTextureGenerator creates Canvas2D-based textures for each face of the sphere.
 *
 * Each texture encodes:
 * - Terrain base colors (biome-aware fill per tile)
 * - Grid lines (subtle dark borders between tiles)
 * - Building icons (simple glyphs for buildings placed on tiles)
 *
 * Resource rendering is handled by vertex colors in ChunkManager (smooth glow effect).
 *
 * Textures are applied as THREE.CanvasTexture on face materials.
 * Regenerated when terrain/buildings change, or on LOD transitions.
 */

// Terrain colors (matching game_renderer.js palette)
const TERRAIN_FILLS = {
  grassland: "#4a7c3f",
  desert: "#c2a64e",
  tundra: "#a8c8d8",
  forest: "#2d5a27",
  volcanic: "#6b2020",
};

// Building icon colors
const BUILDING_FILLS = {
  miner: "#8b6914",
  conveyor: "#888888",
  smelter: "#cc4411",
  assembler: "#3366aa",
  splitter: "#22aa88",
  merger: "#8844aa",
};

// Building icon glyphs (drawn procedurally)
const BUILDING_GLYPHS = {
  miner: drawMinerGlyph,
  conveyor: drawConveyorGlyph,
  smelter: drawSmelterGlyph,
  assembler: drawAssemblerGlyph,
  splitter: drawSplitterGlyph,
  merger: drawMergerGlyph,
};

const PIXELS_PER_TILE = 32;

export class TileTextureGenerator {
  /**
   * @param {number} maxSubdivisions - full-resolution grid size (e.g. 16)
   * @param {Array<Array<Array<{t:string, r:string|null}>>>} terrainData - per-face terrain
   */
  constructor(maxSubdivisions, terrainData) {
    this.maxSubdivisions = maxSubdivisions;
    this.terrainData = terrainData;
    this.textures = []; // THREE.CanvasTexture per face (or null)
    this.canvases = []; // HTMLCanvasElement per face (or null)

    for (let i = 0; i < 30; i++) {
      this.textures.push(null);
      this.canvases.push(null);
    }
  }

  /**
   * Generate (or regenerate) the texture for a face at a given LOD subdivision.
   * @param {number} faceId
   * @param {number} N - subdivision count at current LOD
   * @param {object} buildings - Map of "face:row:col" -> {type, orientation}
   * @returns {THREE.CanvasTexture}
   */
  generateTexture(faceId, N, buildings) {
    const fullN = this.maxSubdivisions;
    const pxPerTile = PIXELS_PER_TILE;
    const size = N * pxPerTile;

    let canvas = this.canvases[faceId];
    if (!canvas || canvas.width !== size || canvas.height !== size) {
      canvas = document.createElement("canvas");
      canvas.width = size;
      canvas.height = size;
      this.canvases[faceId] = canvas;
    }

    const ctx = canvas.getContext("2d");
    const faceTerrain = this.terrainData[faceId];

    // Draw each tile
    for (let row = 0; row < N; row++) {
      for (let col = 0; col < N; col++) {
        const x = col * pxPerTile;
        const y = row * pxPerTile;

        // Map LOD tile to full-res terrain (center sample)
        const fullRow = Math.min(Math.floor(((row + 0.5) / N) * fullN), fullN - 1);
        const fullCol = Math.min(Math.floor(((col + 0.5) / N) * fullN), fullN - 1);
        const td = faceTerrain[fullRow][fullCol];

        // Terrain base fill
        const terrainColor = TERRAIN_FILLS[td.t] || TERRAIN_FILLS.grassland;
        ctx.fillStyle = terrainColor;
        ctx.fillRect(x, y, pxPerTile, pxPerTile);

        // Building icon
        const buildingKey = `${faceId}:${fullRow}:${fullCol}`;
        const building = buildings.get ? buildings.get(buildingKey) : buildings[buildingKey];
        if (building) {
          drawBuildingIcon(ctx, x, y, pxPerTile, building.type, building.orientation);
        }

        // Grid line borders
        ctx.strokeStyle = "rgba(0, 0, 0, 0.2)";
        ctx.lineWidth = 1;
        ctx.strokeRect(x + 0.5, y + 0.5, pxPerTile - 1, pxPerTile - 1);
      }
    }

    // Create or update texture
    if (this.textures[faceId]) {
      this.textures[faceId].dispose();
    }

    const texture = new THREE.CanvasTexture(canvas);
    texture.minFilter = THREE.LinearMipmapLinearFilter;
    texture.magFilter = THREE.LinearFilter;
    texture.wrapS = THREE.ClampToEdgeWrapping;
    texture.wrapT = THREE.ClampToEdgeWrapping;
    this.textures[faceId] = texture;

    return texture;
  }

  /**
   * Mark a face's texture as needing update (e.g. after building change).
   */
  invalidate(faceId) {
    if (this.textures[faceId]) {
      this.textures[faceId].needsUpdate = true;
    }
  }

  /**
   * Get the texture for a face, or null if not generated.
   */
  getTexture(faceId) {
    return this.textures[faceId];
  }

  dispose() {
    for (let i = 0; i < 30; i++) {
      if (this.textures[i]) {
        this.textures[i].dispose();
        this.textures[i] = null;
      }
      this.canvases[i] = null;
    }
  }
}

// --- Building icon drawing ---

function drawBuildingIcon(ctx, x, y, size, type, orientation) {
  const cx = x + size / 2;
  const cy = y + size / 2;
  const r = size * 0.3;

  ctx.save();
  ctx.translate(cx, cy);

  // Rotate based on orientation: 0=W, 1=S, 2=E, 3=N
  const angle = (orientation || 0) * (Math.PI / 2);
  ctx.rotate(angle);

  const color = BUILDING_FILLS[type] || "#ffffff";
  ctx.fillStyle = color;
  ctx.strokeStyle = "rgba(255,255,255,0.6)";
  ctx.lineWidth = 1.5;

  const glyph = BUILDING_GLYPHS[type];
  if (glyph) {
    glyph(ctx, r);
  } else {
    // Fallback: simple circle
    ctx.beginPath();
    ctx.arc(0, 0, r, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
  }

  ctx.restore();
}

function drawMinerGlyph(ctx, r) {
  // Drill-like triangle pointing down
  ctx.beginPath();
  ctx.moveTo(0, -r);
  ctx.lineTo(-r * 0.7, r * 0.5);
  ctx.lineTo(r * 0.7, r * 0.5);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();

  // Small circle at top (wheel)
  ctx.beginPath();
  ctx.arc(0, -r * 0.5, r * 0.25, 0, Math.PI * 2);
  ctx.stroke();
}

function drawConveyorGlyph(ctx, r) {
  // Arrow pointing right (in un-rotated frame)
  ctx.beginPath();
  ctx.moveTo(-r, -r * 0.3);
  ctx.lineTo(r * 0.3, -r * 0.3);
  ctx.lineTo(r * 0.3, -r * 0.6);
  ctx.lineTo(r, 0);
  ctx.lineTo(r * 0.3, r * 0.6);
  ctx.lineTo(r * 0.3, r * 0.3);
  ctx.lineTo(-r, r * 0.3);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();
}

function drawSmelterGlyph(ctx, r) {
  // Box body
  ctx.fillRect(-r * 0.7, -r * 0.4, r * 1.4, r * 0.9);
  ctx.strokeRect(-r * 0.7, -r * 0.4, r * 1.4, r * 0.9);

  // Chimney
  ctx.fillRect(r * 0.2, -r * 0.9, r * 0.3, r * 0.5);
  ctx.strokeRect(r * 0.2, -r * 0.9, r * 0.3, r * 0.5);
}

function drawAssemblerGlyph(ctx, r) {
  // Gear-like shape
  ctx.beginPath();
  const teeth = 6;
  for (let i = 0; i < teeth; i++) {
    const a1 = (i / teeth) * Math.PI * 2;
    const a2 = ((i + 0.5) / teeth) * Math.PI * 2;
    ctx.lineTo(Math.cos(a1) * r, Math.sin(a1) * r);
    ctx.lineTo(Math.cos(a2) * r * 0.6, Math.sin(a2) * r * 0.6);
  }
  ctx.closePath();
  ctx.fill();
  ctx.stroke();
}

function drawSplitterGlyph(ctx, r) {
  // Y-shape: one input, two outputs
  ctx.beginPath();
  ctx.moveTo(-r, 0);
  ctx.lineTo(0, 0);
  ctx.lineTo(r * 0.7, -r * 0.7);
  ctx.moveTo(0, 0);
  ctx.lineTo(r * 0.7, r * 0.7);
  ctx.lineWidth = r * 0.3;
  ctx.stroke();
  ctx.lineWidth = 1.5;
}

function drawMergerGlyph(ctx, r) {
  // Inverted Y: two inputs, one output
  ctx.beginPath();
  ctx.moveTo(-r * 0.7, -r * 0.7);
  ctx.lineTo(0, 0);
  ctx.lineTo(r, 0);
  ctx.moveTo(-r * 0.7, r * 0.7);
  ctx.lineTo(0, 0);
  ctx.lineWidth = r * 0.3;
  ctx.stroke();
  ctx.lineWidth = 1.5;
}
