import * as THREE from "three";

/**
 * TileTextureGenerator creates Canvas2D-based textures for each cell of the sphere.
 *
 * Each texture encodes:
 * - Terrain base colors (biome-aware fill per tile)
 * - Grid lines (subtle dark borders between tiles)
 * - Building icons (simple glyphs for buildings placed on tiles)
 *
 * Textures are applied as THREE.CanvasTexture on cell materials.
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
  refinery: "#2288aa",
  splitter: "#22aa88",
  merger: "#8844aa",
  submission_terminal: "#aa8833",
};

// Building icon glyphs (drawn procedurally)
const BUILDING_GLYPHS = {
  miner: drawMinerGlyph,
  conveyor: drawConveyorGlyph,
  smelter: drawSmelterGlyph,
  assembler: drawAssemblerGlyph,
  refinery: drawRefineryGlyph,
  splitter: drawSplitterGlyph,
  merger: drawMergerGlyph,
  submission_terminal: drawSubmissionTerminalGlyph,
};

const PIXELS_PER_TILE = 32;
const TILES_PER_CELL = 16;

export class TileTextureGenerator {
  /**
   * @param {number} maxSubdivisions - full-resolution grid size (e.g. 64)
   */
  constructor(maxSubdivisions) {
    this.maxSubdivisions = maxSubdivisions;
    this.tilesPerCell = TILES_PER_CELL;
    // Keyed by cellKey (faceId * 16 + cellRow * 4 + cellCol)
    this.textures = new Map();
    this.canvases = new Map();
  }

  /**
   * Generate (or regenerate) the texture for a cell at a given LOD subdivision.
   * @param {number} faceId
   * @param {number} cellRow - 0-3
   * @param {number} cellCol - 0-3
   * @param {number} N - subdivision count at current LOD within the cell
   * @param {Array} terrainData - terrainData[faceId] = array[64][64] of {t, r}
   * @param {Map|null} buildings - Map of "face:row:col" -> {type, orientation}
   * @returns {THREE.CanvasTexture}
   */
  generateTexture(faceId, cellRow, cellCol, N, terrainData, buildings) {
    const cellKey = faceId * 16 + cellRow * 4 + cellCol;
    const pxPerTile = PIXELS_PER_TILE;
    const size = N * pxPerTile;

    let canvas = this.canvases.get(cellKey);
    if (!canvas || canvas.width !== size || canvas.height !== size) {
      canvas = document.createElement("canvas");
      canvas.width = size;
      canvas.height = size;
      this.canvases.set(cellKey, canvas);
    }

    const ctx = canvas.getContext("2d");
    const faceTerrain = terrainData ? terrainData[faceId] : null;

    // Draw each tile
    for (let row = 0; row < N; row++) {
      for (let col = 0; col < N; col++) {
        const x = col * pxPerTile;
        const y = row * pxPerTile;

        // Map cell-local LOD tile to face-global full-res
        const localFullRow = Math.min(
          Math.floor(((row + 0.5) / N) * this.tilesPerCell),
          this.tilesPerCell - 1
        );
        const localFullCol = Math.min(
          Math.floor(((col + 0.5) / N) * this.tilesPerCell),
          this.tilesPerCell - 1
        );
        const faceRow = cellRow * this.tilesPerCell + localFullRow;
        const faceCol = cellCol * this.tilesPerCell + localFullCol;

        // Terrain base fill
        let terrainColor = TERRAIN_FILLS.grassland;
        if (faceTerrain && faceTerrain[faceRow] && faceTerrain[faceRow][faceCol]) {
          const td = faceTerrain[faceRow][faceCol];
          terrainColor = TERRAIN_FILLS[td.t] || TERRAIN_FILLS.grassland;
        }
        ctx.fillStyle = terrainColor;
        ctx.fillRect(x, y, pxPerTile, pxPerTile);

        // Building icon (only drawn when buildings data is provided)
        if (buildings) {
          const buildingKey = `${faceId}:${faceRow}:${faceCol}`;
          const building = buildings.get ? buildings.get(buildingKey) : buildings[buildingKey];
          if (building) {
            drawBuildingIcon(ctx, x, y, pxPerTile, building.type, building.orientation);
          }
        }

        // Grid line borders
        ctx.strokeStyle = "rgba(0, 0, 0, 0.2)";
        ctx.lineWidth = 1;
        ctx.strokeRect(x + 0.5, y + 0.5, pxPerTile - 1, pxPerTile - 1);
      }
    }

    // Create or update texture
    if (this.textures.has(cellKey)) {
      this.textures.get(cellKey).dispose();
    }

    const texture = new THREE.CanvasTexture(canvas);
    texture.minFilter = THREE.LinearMipmapLinearFilter;
    texture.magFilter = THREE.LinearFilter;
    texture.wrapS = THREE.ClampToEdgeWrapping;
    texture.wrapT = THREE.ClampToEdgeWrapping;
    this.textures.set(cellKey, texture);

    return texture;
  }

  dispose() {
    for (const [, texture] of this.textures) {
      texture.dispose();
    }
    this.textures.clear();
    this.canvases.clear();
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

function drawRefineryGlyph(ctx, r) {
  // Two circles (tanks) connected by a line (pipe)
  ctx.beginPath();
  ctx.arc(-r * 0.3, 0, r * 0.5, 0, Math.PI * 2);
  ctx.fill();
  ctx.stroke();

  ctx.beginPath();
  ctx.arc(r * 0.4, 0, r * 0.35, 0, Math.PI * 2);
  ctx.fill();
  ctx.stroke();

  // Pipe
  ctx.beginPath();
  ctx.moveTo(-r * 0.3, -r * 0.4);
  ctx.lineTo(r * 0.4, -r * 0.4);
  ctx.lineWidth = r * 0.15;
  ctx.stroke();
  ctx.lineWidth = 1.5;
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

function drawSubmissionTerminalGlyph(ctx, r) {
  // Box with an arrow pointing into it (item sink)
  ctx.fillRect(-r * 0.6, -r * 0.5, r * 1.2, r * 1.0);
  ctx.strokeRect(-r * 0.6, -r * 0.5, r * 1.2, r * 1.0);

  // Inward arrow (from left toward center)
  ctx.strokeStyle = "rgba(0,0,0,0.5)";
  ctx.lineWidth = r * 0.2;
  ctx.beginPath();
  ctx.moveTo(-r * 0.9, 0);
  ctx.lineTo(-r * 0.2, 0);
  ctx.stroke();
  ctx.strokeStyle = "rgba(255,255,255,0.6)";
  ctx.lineWidth = 1.5;
}
