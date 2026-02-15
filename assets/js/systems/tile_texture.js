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
  conveyor_mk2: "#aaaacc",
  conveyor_mk3: "#ccccee",
  smelter: "#cc4411",
  assembler: "#3366aa",
  refinery: "#2288aa",
  splitter: "#22aa88",
  merger: "#8844aa",
  balancer: "#44bb99",
  storage_container: "#997744",
  underground_conduit: "#6655aa",
  submission_terminal: "#aa8833",
  containment_trap: "#664488",
  purification_beacon: "#44aadd",
  defense_turret: "#cc3333",
  claim_beacon: "#33aa55",
  trade_terminal: "#ddaa33",
  crossover: "#77aa77",
};

// Building icon glyphs (drawn procedurally)
const BUILDING_GLYPHS = {
  miner: drawMinerGlyph,
  conveyor: drawConveyorGlyph,
  conveyor_mk2: drawConveyorMk2Glyph,
  conveyor_mk3: drawConveyorMk3Glyph,
  smelter: drawSmelterGlyph,
  assembler: drawAssemblerGlyph,
  refinery: drawRefineryGlyph,
  splitter: drawSplitterGlyph,
  merger: drawMergerGlyph,
  balancer: drawBalancerGlyph,
  storage_container: drawStorageContainerGlyph,
  underground_conduit: drawUndergroundConduitGlyph,
  submission_terminal: drawSubmissionTerminalGlyph,
  containment_trap: drawContainmentTrapGlyph,
  purification_beacon: drawPurificationBeaconGlyph,
  defense_turret: drawDefenseTurretGlyph,
  claim_beacon: drawClaimBeaconGlyph,
  trade_terminal: drawTradeTerminalGlyph,
  crossover: drawCrossoverGlyph,
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

        // Building icon — skip at low LOD where tiles are too small
        if (buildings && N > 4) {
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

    // Reuse existing texture if canvas is the same object (same LOD level);
    // just flag it for GPU re-upload instead of allocating a new one.
    const existing = this.textures.get(cellKey);
    if (existing && existing.image === canvas) {
      existing.needsUpdate = true;
      return existing;
    }

    if (existing) existing.dispose();

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

function drawConveyorMk2Glyph(ctx, r) {
  // Double arrow pointing right (faster conveyor)
  ctx.beginPath();
  ctx.moveTo(-r, -r * 0.3);
  ctx.lineTo(r * 0.2, -r * 0.3);
  ctx.lineTo(r * 0.2, -r * 0.5);
  ctx.lineTo(r * 0.7, 0);
  ctx.lineTo(r * 0.2, r * 0.5);
  ctx.lineTo(r * 0.2, r * 0.3);
  ctx.lineTo(-r, r * 0.3);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();

  // Second speed line
  ctx.beginPath();
  ctx.moveTo(-r * 0.6, -r * 0.15);
  ctx.lineTo(-r * 0.2, -r * 0.15);
  ctx.lineTo(-r * 0.2, r * 0.15);
  ctx.lineTo(-r * 0.6, r * 0.15);
  ctx.strokeStyle = "rgba(255,255,255,0.8)";
  ctx.stroke();
  ctx.strokeStyle = "rgba(255,255,255,0.6)";
}

function drawConveyorMk3Glyph(ctx, r) {
  // Triple arrow pointing right (fastest conveyor)
  ctx.beginPath();
  ctx.moveTo(-r, -r * 0.3);
  ctx.lineTo(r * 0.2, -r * 0.3);
  ctx.lineTo(r * 0.2, -r * 0.5);
  ctx.lineTo(r * 0.8, 0);
  ctx.lineTo(r * 0.2, r * 0.5);
  ctx.lineTo(r * 0.2, r * 0.3);
  ctx.lineTo(-r, r * 0.3);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();

  // Triple speed lines
  ctx.strokeStyle = "rgba(255,255,255,0.8)";
  ctx.lineWidth = r * 0.1;
  for (let i = 0; i < 3; i++) {
    const x = -r * 0.8 + i * r * 0.25;
    ctx.beginPath();
    ctx.moveTo(x, -r * 0.15);
    ctx.lineTo(x, r * 0.15);
    ctx.stroke();
  }
  ctx.strokeStyle = "rgba(255,255,255,0.6)";
  ctx.lineWidth = 1.5;
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

function drawBalancerGlyph(ctx, r) {
  // Y-shape with a balance beam across the outputs
  ctx.beginPath();
  ctx.moveTo(-r, 0);
  ctx.lineTo(0, 0);
  ctx.lineTo(r * 0.7, -r * 0.7);
  ctx.moveTo(0, 0);
  ctx.lineTo(r * 0.7, r * 0.7);
  ctx.lineWidth = r * 0.3;
  ctx.stroke();
  ctx.lineWidth = 1.5;

  // Balance indicator (horizontal line across outputs)
  ctx.strokeStyle = "rgba(255,255,255,0.9)";
  ctx.lineWidth = r * 0.15;
  ctx.beginPath();
  ctx.moveTo(r * 0.5, -r * 0.5);
  ctx.lineTo(r * 0.5, r * 0.5);
  ctx.stroke();
  ctx.strokeStyle = "rgba(255,255,255,0.6)";
  ctx.lineWidth = 1.5;
}

function drawStorageContainerGlyph(ctx, r) {
  // Large box (crate)
  ctx.fillRect(-r * 0.8, -r * 0.7, r * 1.6, r * 1.4);
  ctx.strokeRect(-r * 0.8, -r * 0.7, r * 1.6, r * 1.4);

  // Cross straps on crate
  ctx.strokeStyle = "rgba(255,255,255,0.5)";
  ctx.lineWidth = r * 0.1;
  ctx.beginPath();
  ctx.moveTo(-r * 0.8, 0);
  ctx.lineTo(r * 0.8, 0);
  ctx.moveTo(0, -r * 0.7);
  ctx.lineTo(0, r * 0.7);
  ctx.stroke();
  ctx.strokeStyle = "rgba(255,255,255,0.6)";
  ctx.lineWidth = 1.5;
}

function drawUndergroundConduitGlyph(ctx, r) {
  // Portal ring
  ctx.beginPath();
  ctx.arc(0, 0, r * 0.7, 0, Math.PI * 2);
  ctx.fill();
  ctx.stroke();

  // Inner portal (darker)
  ctx.fillStyle = "rgba(50,30,100,0.6)";
  ctx.beginPath();
  ctx.arc(0, 0, r * 0.4, 0, Math.PI * 2);
  ctx.fill();

  // Direction arrow inside
  ctx.strokeStyle = "rgba(255,255,255,0.8)";
  ctx.lineWidth = r * 0.15;
  ctx.beginPath();
  ctx.moveTo(-r * 0.2, 0);
  ctx.lineTo(r * 0.2, 0);
  ctx.lineTo(r * 0.1, -r * 0.15);
  ctx.moveTo(r * 0.2, 0);
  ctx.lineTo(r * 0.1, r * 0.15);
  ctx.stroke();
  ctx.strokeStyle = "rgba(255,255,255,0.6)";
  ctx.lineWidth = 1.5;
}

function drawCrossoverGlyph(ctx, r) {
  // Plus/cross shape — two perpendicular streams
  ctx.beginPath();
  // Horizontal bar
  ctx.moveTo(-r, -r * 0.25);
  ctx.lineTo(r, -r * 0.25);
  ctx.lineTo(r, r * 0.25);
  ctx.lineTo(-r, r * 0.25);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();

  ctx.beginPath();
  // Vertical bar
  ctx.moveTo(-r * 0.25, -r);
  ctx.lineTo(r * 0.25, -r);
  ctx.lineTo(r * 0.25, r);
  ctx.lineTo(-r * 0.25, r);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();

  // Center dot
  ctx.beginPath();
  ctx.arc(0, 0, r * 0.15, 0, Math.PI * 2);
  ctx.strokeStyle = "rgba(255,255,255,0.9)";
  ctx.stroke();
  ctx.strokeStyle = "rgba(255,255,255,0.6)";
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

function drawContainmentTrapGlyph(ctx, r) {
  // Diamond (rotated square) with a circle inside
  ctx.beginPath();
  ctx.moveTo(0, -r);
  ctx.lineTo(r, 0);
  ctx.lineTo(0, r);
  ctx.lineTo(-r, 0);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();

  // Inner circle (containment field)
  ctx.beginPath();
  ctx.arc(0, 0, r * 0.4, 0, Math.PI * 2);
  ctx.strokeStyle = "rgba(255,255,255,0.8)";
  ctx.stroke();
  ctx.strokeStyle = "rgba(255,255,255,0.6)";
}

function drawPurificationBeaconGlyph(ctx, r) {
  // Hexagon with radiating lines (purification field)
  ctx.beginPath();
  for (let i = 0; i < 6; i++) {
    const angle = (i / 6) * Math.PI * 2 - Math.PI / 2;
    const x = Math.cos(angle) * r * 0.8;
    const y = Math.sin(angle) * r * 0.8;
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.closePath();
  ctx.fill();
  ctx.stroke();

  // Center dot (emitter)
  ctx.beginPath();
  ctx.arc(0, 0, r * 0.25, 0, Math.PI * 2);
  ctx.strokeStyle = "rgba(255,255,255,0.9)";
  ctx.stroke();
  ctx.strokeStyle = "rgba(255,255,255,0.6)";
}

function drawDefenseTurretGlyph(ctx, r) {
  // Square base with barrel pointing right
  ctx.fillRect(-r * 0.5, -r * 0.5, r * 1.0, r * 1.0);
  ctx.strokeRect(-r * 0.5, -r * 0.5, r * 1.0, r * 1.0);

  // Barrel
  ctx.fillRect(r * 0.2, -r * 0.15, r * 0.8, r * 0.3);
  ctx.strokeRect(r * 0.2, -r * 0.15, r * 0.8, r * 0.3);

  // Muzzle flash dot
  ctx.beginPath();
  ctx.arc(r * 0.9, 0, r * 0.12, 0, Math.PI * 2);
  ctx.fillStyle = "rgba(255,50,50,0.8)";
  ctx.fill();
}

function drawClaimBeaconGlyph(ctx, r) {
  // Hexagonal base with a flag/diamond on top
  ctx.beginPath();
  for (let i = 0; i < 6; i++) {
    const angle = (i / 6) * Math.PI * 2 - Math.PI / 2;
    const x = Math.cos(angle) * r * 0.7;
    const y = Math.sin(angle) * r * 0.7;
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.closePath();
  ctx.fill();
  ctx.stroke();

  // Flag diamond in center
  ctx.beginPath();
  ctx.moveTo(0, -r * 0.4);
  ctx.lineTo(r * 0.25, 0);
  ctx.lineTo(0, r * 0.4);
  ctx.lineTo(-r * 0.25, 0);
  ctx.closePath();
  ctx.strokeStyle = "rgba(255,255,255,0.9)";
  ctx.stroke();
  ctx.strokeStyle = "rgba(255,255,255,0.6)";
}

function drawTradeTerminalGlyph(ctx, r) {
  // Two boxes with arrows between them (exchange)
  ctx.fillRect(-r * 0.8, -r * 0.4, r * 0.6, r * 0.8);
  ctx.strokeRect(-r * 0.8, -r * 0.4, r * 0.6, r * 0.8);

  ctx.fillRect(r * 0.2, -r * 0.4, r * 0.6, r * 0.8);
  ctx.strokeRect(r * 0.2, -r * 0.4, r * 0.6, r * 0.8);

  // Exchange arrows (bidirectional)
  ctx.strokeStyle = "rgba(255,255,255,0.8)";
  ctx.lineWidth = r * 0.15;
  ctx.beginPath();
  ctx.moveTo(-r * 0.15, -r * 0.15);
  ctx.lineTo(r * 0.15, -r * 0.15);
  ctx.moveTo(r * 0.15, r * 0.15);
  ctx.lineTo(-r * 0.15, r * 0.15);
  ctx.stroke();
  ctx.strokeStyle = "rgba(255,255,255,0.6)";
  ctx.lineWidth = 1.5;
}
