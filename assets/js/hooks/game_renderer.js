import * as THREE from "three";
import { createBuildingMesh } from "../buildings/building_factory.js";
import { ItemInterpolator } from "../systems/item_interpolator.js";
import { ItemRenderer } from "../systems/item_renderer.js";
import { CreatureRenderer } from "../systems/creature_renderer.js";
import { ChunkManager } from "../systems/chunk_manager.js";
import { TileTextureGenerator } from "../systems/tile_texture.js";
import { AtmosphereRenderer } from "../systems/atmosphere.js";
import { DroneCamera } from "../systems/drone_camera.js";
import { PlayerPresence } from "../systems/player_presence.js";
import { PathfindingEngine } from "../systems/pathfinding.js";
import { PlacementPreview } from "../systems/placement_preview.js";
import { LineDrawingTool } from "../systems/line_drawing_tool.js";
import { DemolishTool } from "../systems/demolish_tool.js";
import { BlueprintTool } from "../systems/blueprint_tool.js";
import { TerritoryRenderer } from "../systems/territory_renderer.js";
import { CorruptionRenderer } from "../systems/corruption_renderer.js";
import { AlteredItemRenderer } from "../systems/altered_item_renderer.js";

// Terrain biome colors (shared with ChunkManager)
const TERRAIN_COLORS = {
  grassland: new THREE.Color(0x4a7c3f),
  desert: new THREE.Color(0xc2a64e),
  tundra: new THREE.Color(0xa8c8d8),
  forest: new THREE.Color(0x2d5a27),
  volcanic: new THREE.Color(0x6b2020),
};

// Resource accent colors (blended with terrain) — stronger contrast
const RESOURCE_ACCENTS = {
  iron: new THREE.Color(0xd4722a),
  copper: new THREE.Color(0x30c9a8),
  quartz: new THREE.Color(0xd4b8ff),
  titanium: new THREE.Color(0x556677),
  oil: new THREE.Color(0x1a1a2e),
  sulfur: new THREE.Color(0xcccc22),
};

// Direction offsets: orientation -> [dRow, dCol]
// 0=W (col+1), 1=S (row+1), 2=E (col-1), 3=N (row-1)
const DIR_OFFSETS = [
  [0, 1],   // W
  [1, 0],   // S
  [0, -1],  // E
  [-1, 0],  // N
];

const GameRenderer = {
  mounted() {
    const data = JSON.parse(this.el.dataset.geometry);
    this.subdivisions = data.subdivisions;

    // Unpack flat vertex array into vec3 array
    this.baseVertices = [];
    for (let i = 0; i < data.vertices.length; i += 3) {
      this.baseVertices.push(
        new THREE.Vector3(data.vertices[i], data.vertices[i + 1], data.vertices[i + 2])
      );
    }
    this.faceIndices = data.faces; // array of 30 arrays of 4 vertex indices

    // Tile state
    this.selectedTile = null; // {face, row, col}
    this.hoveredTile = null;  // {face, row, col}

    // Building state
    this.buildingMeshes = {}; // keyed by "face:row:col"
    this.buildingData = new Map(); // keyed by "face:row:col" -> {type, orientation}
    this.buildingsByCell = new Map(); // "face:cellRow:cellCol" -> Set of building keys
    this.placementType = null;       // current building type being placed
    this.placementOrientation = 0;   // current placement orientation (0-3)
    this.buildingRenderMode = "3d";  // "3d" = meshes visible, "icons" = texture icons visible

    // Line-drawing mode state
    this.lineMode = false;
    this.lineStart = null;

    // Blueprint tool state
    this.blueprintMode = null;         // null | "capture" | "stamp"
    this.blueprintCaptureStart = null;
    this.blueprintPattern = null;

    // Demolish mode state
    this.demolishMode = false;
    this.demolishStart = null;

    // Scene, controls, subsystems
    this.initScene();

    this.chunkManager = new ChunkManager(
      this.scene,
      this.baseVertices,
      this.faceIndices,
      this.subdivisions,
      { terrainColors: TERRAIN_COLORS, resourceAccents: RESOURCE_ACCENTS }
    );

    this.tileTextures = new TileTextureGenerator(this.subdivisions);

    const getTileCenter = (face, row, col) => this.getTileCenter(face, row, col);

    this.droneCamera = new DroneCamera(this.camera, this.renderer, this.chunkManager);

    // Restore drone camera state from localStorage
    try {
      const droneStateStr = localStorage.getItem("spheric_drone_state");
      if (droneStateStr) {
        this.droneCamera.restoreState(JSON.parse(droneStateStr));
      } else {
        // Fall back to old camera position format
        const cx = parseFloat(localStorage.getItem("spheric_camera_x"));
        const cy = parseFloat(localStorage.getItem("spheric_camera_y"));
        const cz = parseFloat(localStorage.getItem("spheric_camera_z"));
        if (cx && cy && cz) {
          this.droneCamera.restoreFromCameraPos(cx, cy, cz);
        }
      }
    } catch (_e) { /* localStorage unavailable */ }

    this.pathfinding = new PathfindingEngine(this.faceIndices, this.subdivisions, getTileCenter);

    this.placementPreview = new PlacementPreview(this.scene, getTileCenter, this.subdivisions);

    this.lineDrawingTool = new LineDrawingTool(
      this.scene, getTileCenter, this.chunkManager, this.subdivisions
    );

    this.demolishTool = new DemolishTool(this.chunkManager);

    this.blueprintTool = new BlueprintTool(this.chunkManager, this.pathfinding);

    this.territoryRenderer = new TerritoryRenderer(this.scene, getTileCenter, this.subdivisions);

    this.corruptionRenderer = new CorruptionRenderer(this.scene, getTileCenter, this.subdivisions);

    this.alteredItemRenderer = new AlteredItemRenderer(this.scene, getTileCenter);

    this.playerPresence = new PlayerPresence(this.scene);

    this.atmosphere = new AtmosphereRenderer(this.scene);

    this.itemInterpolator = new ItemInterpolator();
    this.itemRenderer = new ItemRenderer(this.scene, getTileCenter);

    this.creatureRenderer = new CreatureRenderer(this.scene, getTileCenter);
    this.creatureData = [];

    this.setupRaycasting();
    this.setupCameraTracking();
    this.setupEventHandlers();

    // Do initial LOD update with starting camera position
    this.chunkManager.update(this.camera.position);

    this.animate();

    this._onResize = () => this.onResize();
    window.addEventListener("resize", this._onResize);
  },

  initScene() {
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x060608);
    this.scene.fog = new THREE.FogExp2(0x060608, 0.15);

    this.camera = new THREE.PerspectiveCamera(
      60,
      window.innerWidth / window.innerHeight,
      0.01,
      100
    );
    this.camera.position.set(0, 0, 3.5);

    this.renderer = new THREE.WebGLRenderer({ antialias: true });
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.el.appendChild(this.renderer.domElement);

    // DroneCamera is initialized after ChunkManager in mounted()

    // Atmosphere lighting — sun direction driven by shift cycle
    this.ambientLight = new THREE.AmbientLight(0x404050, 1.2);
    this.scene.add(this.ambientLight);
    this.dirLight = new THREE.DirectionalLight(0xeeeeff, 0.8);
    this.dirLight.position.set(5, 0, 0);
    this.scene.add(this.dirLight);
    const fillLight = new THREE.DirectionalLight(0x6666aa, 0.15);
    fillLight.position.set(-3, -2, -4);
    this.scene.add(fillLight);
  },

  // --- Tile center computation (always at full resolution) ---

  getTileCenter(faceId, row, col) {
    return this.chunkManager.getTileCenter(faceId, row, col);
  },

  // --- Building placement on sphere ---

  addBuildingToScene(face, row, col, type, orientation, underConstruction = false) {
    const key = `${face}:${row}:${col}`;

    // Track building data for texture regeneration
    this.buildingData.set(key, { type, orientation });

    // Remove existing mesh if any
    if (this.buildingMeshes[key]) {
      this.scene.remove(this.buildingMeshes[key]);
    }

    const mesh = createBuildingMesh(type);

    // Apply ghost effect for construction sites
    if (underConstruction) {
      mesh.traverse((child) => {
        if (child.isMesh && child.material) {
          // Clone material so we don't affect shared materials
          child.material = child.material.clone();
          child.material.transparent = true;
          child.material.opacity = 0.35;
          child.material.wireframe = true;
          child.material._shared = false;
        }
      });
      mesh.userData.underConstruction = true;
    }

    const normal = this.getTileCenter(face, row, col).normalize();

    // Position slightly above surface
    mesh.position.copy(normal).multiplyScalar(1.001);

    // Compute forward direction from this tile toward the neighbor in the
    // orientation direction, so buildings point exactly at their output tile.
    const [dr, dc] = DIR_OFFSETS[orientation];
    const neighborCenter = this.getTileCenter(face, row + dr, col + dc);

    // Project neighbor direction onto tangent plane at this tile
    const toNeighbor = new THREE.Vector3().subVectors(neighborCenter, normal);
    const tangentX = toNeighbor.addScaledVector(normal, -toNeighbor.dot(normal)).normalize();
    const tangentZ = new THREE.Vector3().crossVectors(tangentX, normal).normalize();

    const m = new THREE.Matrix4().makeBasis(tangentX, normal, tangentZ);
    mesh.quaternion.setFromRotationMatrix(m);

    this.scene.add(mesh);
    this.buildingMeshes[key] = mesh;

    // Index by cell for LOD-aware visibility
    const { cellRow, cellCol } = this.chunkManager.toCellCoords(row, col);
    const cellKey = `${face}:${cellRow}:${cellCol}`;
    if (!this.buildingsByCell.has(cellKey)) {
      this.buildingsByCell.set(cellKey, new Set());
    }
    this.buildingsByCell.get(cellKey).add(key);

    // Apply visibility based on current cell LOD and camera distance
    this.updateBuildingVisibility(face, cellRow, cellCol);

    // Regenerate tile texture for the affected cell
    this.regenerateCellTexture(face, cellRow, cellCol);
  },

  disposeMeshGroup(group) {
    group.traverse((child) => {
      if (child.isMesh) {
        if (child.geometry && !child.geometry._shared) child.geometry.dispose();
        if (child.material && !child.material._shared) child.material.dispose();
      }
      if (child.isLine) {
        if (child.geometry) child.geometry.dispose();
        if (child.material) child.material.dispose();
      }
    });
  },

  removeBuildingFromScene(face, row, col) {
    const key = `${face}:${row}:${col}`;
    const mesh = this.buildingMeshes[key];
    if (mesh) {
      this.scene.remove(mesh);
      delete this.buildingMeshes[key];
    }
    this.buildingData.delete(key);

    // Remove from cell index
    const { cellRow, cellCol } = this.chunkManager.toCellCoords(row, col);
    const cellKey = `${face}:${cellRow}:${cellCol}`;
    const cellSet = this.buildingsByCell.get(cellKey);
    if (cellSet) {
      cellSet.delete(key);
      if (cellSet.size === 0) this.buildingsByCell.delete(cellKey);
    }

    // Regenerate tile texture for the affected cell
    this.regenerateCellTexture(face, cellRow, cellCol);
  },

  regenerateCellTexture(faceId, cellRow, cellCol) {
    const N = this.chunkManager.getCellLOD(faceId, cellRow, cellCol);
    if (N === 0) return;
    if (!this.chunkManager.terrainData[faceId]) return;

    const showIcons = this.buildingRenderMode === "icons";
    const texture = this.tileTextures.generateTexture(
      faceId, cellRow, cellCol, N,
      this.chunkManager.terrainData,
      showIcons ? this.buildingData : null
    );
    const cellKey = this.chunkManager.cellKey(faceId, cellRow, cellCol);
    const cellMesh = this.chunkManager.cellMeshes.get(cellKey);
    if (cellMesh) {
      cellMesh.material.map = texture;
      cellMesh.material.needsUpdate = true;
    }
  },

  // --- LiveView event handlers ---

  setupEventHandlers() {
    this.handleEvent("terrain_face", ({ face, terrain }) => {
      this.chunkManager.terrainData[face] = terrain;
      this.chunkManager.clearFaceCache(face);
      for (let cr = 0; cr < 4; cr++) {
        for (let cc = 0; cc < 4; cc++) {
          const N = this.chunkManager.getCellLOD(face, cr, cc);
          if (N > 0) {
            this.chunkManager.rebuildCell(face, cr, cc, N);
            this.regenerateCellTexture(face, cr, cc);
          }
        }
      }
    });

    this.handleEvent("building_placed", ({ face, row, col, type, orientation, under_construction }) => {
      this.addBuildingToScene(face, row, col, type, orientation, !!under_construction);
    });

    this.handleEvent("building_removed", ({ face, row, col }) => {
      this.removeBuildingFromScene(face, row, col);
    });

    this.handleEvent("construction_complete", ({ face, row, col, type, orientation }) => {
      // Re-add as a fully built building (removes ghost effect)
      this.addBuildingToScene(face, row, col, type, orientation, false);
    });

    this.handleEvent("buildings_snapshot", ({ buildings }) => {
      for (const b of buildings) {
        this.addBuildingToScene(b.face, b.row, b.col, b.type, b.orientation, !!b.under_construction);
      }
    });

    this.handleEvent("tick_items", ({ tick, face, items }) => {
      this.itemInterpolator.onTickUpdate(tick, face, items);
    });

    this.handleEvent("placement_mode", ({ type, orientation }) => {
      this.cancelLineDraw();
      this.cancelDemolishDraw();
      this.placementType = type;
      this.placementOrientation = orientation ?? 0;
      this.placementPreview.clear();
      if (this.placementType && this.hoveredTile && !this.lineMode) {
        this.placementPreview.show(
          this.hoveredTile.face, this.hoveredTile.row, this.hoveredTile.col,
          this.placementOrientation
        );
      }
    });

    this.handleEvent("line_mode", ({ enabled }) => {
      this.cancelLineDraw();
      this.lineMode = enabled;
    });

    this.handleEvent("demolish_mode", ({ enabled }) => {
      this.cancelDemolishDraw();
      this.demolishMode = enabled;
    });

    this.handleEvent("remove_error", ({ face, row, col }) => {
      this.setTileOverlay(face, row, col, "error");
      setTimeout(() => {
        this.setTileOverlay(face, row, col, null);
      }, 300);
    });

    this.handleEvent("restore_player", ({ player_id, player_name, player_color, camera }) => {
      try {
        localStorage.setItem("spheric_player_id", player_id);
        localStorage.setItem("spheric_player_name", player_name);
        localStorage.setItem("spheric_player_color", player_color);
      } catch (_e) { /* localStorage unavailable */ }

      if (camera && camera.z != null) {
        this.droneCamera.restoreFromCameraPos(camera.x, camera.y, camera.z);
      }
    });

    this.handleEvent("save_hotbar", ({ hotbar }) => {
      try {
        localStorage.setItem("spheric_hotbar", JSON.stringify(hotbar));
      } catch (_e) { /* localStorage unavailable */ }
    });

    this.handleEvent("players_update", ({ players }) => {
      this.playerPresence.update(players);
    });

    this.handleEvent("place_error", ({ face, row, col, reason }) => {
      this.setTileOverlay(face, row, col, "error");
      setTimeout(() => {
        const wasSelected =
          this.selectedTile &&
          this.selectedTile.face === face &&
          this.selectedTile.row === row &&
          this.selectedTile.col === col;
        this.setTileOverlay(face, row, col, wasSelected ? "selected" : null);
      }, 300);
    });

    // --- Creature event handlers ---

    this.handleEvent("creature_sync", ({ face, creatures }) => {
      this.creatureData = this.creatureData.filter(c => c.face !== face);
      this.creatureData.push(...creatures);
    });

    this.handleEvent("creature_spawned", ({ id, creature }) => {
      this.creatureRenderer.onCreatureSpawned(id, creature);
      this.creatureData.push({ id, ...creature });
    });

    this.handleEvent("creature_moved", ({ id, creature }) => {
      this.creatureRenderer.onCreatureMoved(id, creature);
      const idx = this.creatureData.findIndex(c => c.id === id);
      if (idx >= 0) {
        this.creatureData[idx] = { id, ...creature };
      } else {
        this.creatureData.push({ id, ...creature });
      }
    });

    this.handleEvent("creature_captured", ({ id }) => {
      this.creatureRenderer.onCreatureCaptured(id);
      this.creatureData = this.creatureData.filter(c => c.id !== id);
    });

    // --- Altered Items ---

    this.handleEvent("altered_items", ({ face, items }) => {
      for (const item of items) {
        this.alteredItemRenderer.addItem(face, item.row, item.col, item.type, item.color);
      }
    });

    // --- Hiss Corruption ---

    this.handleEvent("corruption_sync", ({ face, tiles }) => {
      this.corruptionRenderer.syncFace(face, tiles);
    });

    this.handleEvent("corruption_update", ({ face, tiles }) => {
      for (const tile of tiles) {
        this.corruptionRenderer.addOverlay(tile.face, tile.row, tile.col, tile.intensity);
      }
    });

    this.handleEvent("corruption_cleared", ({ face, tiles }) => {
      for (const tile of tiles) {
        this.corruptionRenderer.removeOverlay(tile.face, tile.row, tile.col);
      }
    });

    // --- Territory ---

    this.handleEvent("territory_update", ({ face, territories }) => {
      this.territoryRenderer.setTerritories(face, territories);
    });

    this.handleEvent("territory_sync", ({ face, territories }) => {
      this.territoryRenderer.setTerritories(face, territories);
    });

    this.handleEvent("hiss_sync", ({ face, entities }) => {
      this.corruptionRenderer.syncHissEntities(face, entities);
    });

    this.handleEvent("hiss_spawned", ({ id, entity }) => {
      this.corruptionRenderer.addHissEntity(id, entity);
    });

    this.handleEvent("hiss_moved", ({ id, entity }) => {
      this.corruptionRenderer.moveHissEntity(id, entity);
    });

    this.handleEvent("hiss_killed", ({ id }) => {
      this.corruptionRenderer.killHissEntity(id);
    });

    this.handleEvent("building_damaged", ({ face, row, col, action }) => {
      this.setTileOverlay(face, row, col, "error");
      setTimeout(() => {
        this.setTileOverlay(face, row, col, null);
      }, 200);
    });

    // Blueprint tool events from LiveView
    this.handleEvent("blueprint_mode", ({ mode }) => {
      this.cancelLineDraw();
      this.cancelDemolishDraw();
      this.placementPreview.clear();
      this.blueprintTool.clearPreview();
      this.blueprintCaptureStart = null;

      if (mode === "capture") {
        this.blueprintMode = "capture";
        this.placementType = null;
      } else if (mode === "stamp") {
        this.blueprintMode = "stamp";
        this.placementType = null;
      } else {
        this.blueprintMode = null;
      }
    });

    this.handleEvent("blueprint_select", ({ index }) => {
      const pattern = this.blueprintTool.selectBlueprint(index);
      if (pattern) {
        this.blueprintPattern = pattern;
        this.blueprintMode = "stamp";
        this.placementType = null;
      }
    });

    // --- Phase 8: Shift Cycle & World Events ---

    this.handleEvent("shift_cycle_changed", ({ phase, ambient, directional, intensity, bg, sun_x, sun_y, sun_z }) => {
      if (this.ambientLight) this.ambientLight.color.setHex(ambient);
      if (this.dirLight) {
        this.dirLight.color.setHex(directional);
        this.dirLight.intensity = intensity;
        if (sun_x !== undefined) {
          this.dirLight.position.set(sun_x * 5, sun_y * 5, sun_z * 5);
        }
      }
      if (this.scene.background) this.scene.background.setHex(bg);
      if (this.scene.fog) this.scene.fog.color.setHex(bg);
    });

    this.handleEvent("sun_moved", ({ sun_x, sun_y, sun_z, phase, ambient, intensity, bg }) => {
      if (this.dirLight) {
        this.dirLight.position.set(sun_x * 5, sun_y * 5, sun_z * 5);
        if (intensity !== undefined) this.dirLight.intensity = intensity;
      }
      if (ambient !== undefined && this.ambientLight) this.ambientLight.color.setHex(ambient);
      if (bg !== undefined) {
        if (this.scene.background) this.scene.background.setHex(bg);
        if (this.scene.fog) this.scene.fog.color.setHex(bg);
      }
    });

    this.handleEvent("local_lighting", ({ phase, ambient, intensity, bg }) => {
      if (this.ambientLight) this.ambientLight.color.setHex(ambient);
      if (this.dirLight && intensity !== undefined) this.dirLight.intensity = intensity;
      if (bg !== undefined) {
        if (this.scene.background) this.scene.background.setHex(bg);
        if (this.scene.fog) this.scene.fog.color.setHex(bg);
      }
    });

    this.handleEvent("world_event_started", ({ event, name, color }) => {
      this._activeWorldEvent = event;
    });

    this.handleEvent("world_event_ended", ({ event }) => {
      this._activeWorldEvent = null;
    });

    this.handleEvent("world_reset", () => {
      setTimeout(() => window.location.reload(), 500);
    });
  },

  // --- Raycasting for tile selection ---

  setupRaycasting() {
    this.raycaster = new THREE.Raycaster();
    this.mouse = new THREE.Vector2();

    this._onClick = (event) => this.onTileClick(event);
    this._onMouseMove = (event) => this.onTileHover(event);
    this._onContextMenu = (event) => this.onTileRightClick(event);
    this.renderer.domElement.addEventListener("click", this._onClick);
    this.renderer.domElement.addEventListener("mousemove", this._onMouseMove);
    this.renderer.domElement.addEventListener("contextmenu", this._onContextMenu);

    this._onKeyDown = (event) => {
      if (event.key === "Escape") {
        if (this.blueprintMode) {
          this.blueprintTool.clearPreview();
          this.blueprintMode = null;
          this.blueprintCaptureStart = null;
          this.pushEvent("blueprint_cancelled", {});
          return;
        }
        if (this.lineStart) {
          this.cancelLineDraw();
          return;
        }
        if (this.demolishStart) {
          this.cancelDemolishDraw();
          return;
        }
      }
      if (event.key === "t" || event.key === "T") {
        this.toggleBuildingRenderMode();
      }
    };
    window.addEventListener("keydown", this._onKeyDown);
  },

  hitToTile(event) {
    this.mouse.x = (event.clientX / window.innerWidth) * 2 - 1;
    this.mouse.y = -(event.clientY / window.innerHeight) * 2 + 1;

    this.raycaster.setFromCamera(this.mouse, this.camera);
    const meshes = this.chunkManager.getRaycastMeshes();
    const intersects = this.raycaster.intersectObjects(meshes);

    if (intersects.length === 0) return null;

    return this.chunkManager.hitToTile(intersects[0]);
  },

  onTileClick(event) {
    if (this.droneCamera.suppressClick) return;

    // Raycast to get the 3D hit point for drone navigation
    const hitPoint = this.droneCamera.raycastSphere(event.clientX, event.clientY);
    if (hitPoint) {
      this.droneCamera.flyTo(hitPoint);
    }

    const tile = this.hitToTile(event);
    if (!tile) return;

    // Demolish mode: two-click rectangle workflow
    if (this.demolishMode) {
      if (!this.demolishStart) {
        this.demolishStart = tile;
        this.setTileOverlay(tile.face, tile.row, tile.col, "selected");
        return;
      } else {
        if (this.demolishStart.face !== tile.face) {
          this.cancelDemolishDraw();
          return;
        }

        const start = this.demolishStart;
        const minRow = Math.min(start.row, tile.row);
        const maxRow = Math.max(start.row, tile.row);
        const minCol = Math.min(start.col, tile.col);
        const maxCol = Math.max(start.col, tile.col);

        const toRemove = [];
        for (let r = minRow; r <= maxRow; r++) {
          for (let c = minCol; c <= maxCol; c++) {
            const key = `${start.face}:${r}:${c}`;
            if (this.buildingData.has(key)) {
              toRemove.push({ face: start.face, row: r, col: c });
            }
          }
        }

        if (toRemove.length > 0) {
          this.pushEvent("remove_area", { tiles: toRemove });
        }

        this.cancelDemolishDraw();
        return;
      }
    }

    // Blueprint mode: capture or stamp
    if (this.blueprintMode) {
      const result = this.blueprintTool.onClick(
        tile, this.blueprintMode, this.blueprintCaptureStart,
        this.blueprintPattern, this.buildingData,
        (event, data) => this.pushEvent(event, data)
      );
      if (result) {
        if (result.action === "capture_start") {
          this.blueprintCaptureStart = result.tile;
        } else if (result.action === "capture_reset" || result.action === "capture_empty") {
          this.blueprintCaptureStart = null;
        } else if (result.action === "captured") {
          this.blueprintPattern = result.pattern;
          this.blueprintMode = "stamp";
          this.blueprintCaptureStart = null;
        }
        return;
      }
    }

    // Line-drawing mode: two-click workflow
    if (this.lineMode && this.placementType) {
      if (!this.lineStart) {
        this.lineStart = tile;
        this.setTileOverlay(tile.face, tile.row, tile.col, "selected");
        return;
      } else {
        const path = this.pathfinding.computeLinePath(
          this.lineStart, tile, this.placementOrientation
        );
        if (path.length > 0) {
          this.pushEvent("place_line", {
            buildings: path.map(t => ({
              face: t.face,
              row: t.row,
              col: t.col,
              orientation: t.orientation,
            })),
          });
        }
        this.cancelLineDraw();
        return;
      }
    }

    // Normal mode: clear previous selection
    if (this.selectedTile) {
      this.setTileOverlay(this.selectedTile.face, this.selectedTile.row, this.selectedTile.col, null);
    }

    this.selectedTile = tile;
    this.setTileOverlay(tile.face, tile.row, tile.col, "selected");

    this.pushEvent("tile_click", {
      face: tile.face,
      row: tile.row,
      col: tile.col,
    });
  },

  onTileRightClick(event) {
    event.preventDefault();
    if (this.droneCamera.isDragging) return;

    if (this.lineStart) {
      this.cancelLineDraw();
      return;
    }
  },

  onTileHover(event) {
    if (this.droneCamera.isDragging) return;
    const tile = this.hitToTile(event);

    // Clear previous hover
    if (this.hoveredTile) {
      const h = this.hoveredTile;
      const overlay = this.getTileOverlay(h.face, h.row, h.col);
      if (overlay === "hover") {
        this.setTileOverlay(h.face, h.row, h.col, null);
      }
    }

    this.placementPreview.clear();
    this.hoveredTile = tile;

    if (tile) {
      // Demolish area preview
      if (this.demolishMode && this.demolishStart) {
        this.demolishTool.showPreview(this.demolishStart, tile, this.buildingData);
        return;
      }

      // Blueprint stamp preview
      if (this.blueprintMode === "stamp" && this.blueprintPattern) {
        this.blueprintTool.showPreview(tile, this.blueprintPattern);
        return;
      }

      // If in line-drawing mode with start set, show line preview
      if (this.lineMode && this.lineStart) {
        const path = this.pathfinding.computeLinePath(
          this.lineStart, tile, this.placementOrientation
        );
        this.lineDrawingTool.showPreview(path);
        return;
      }

      const overlay = this.getTileOverlay(tile.face, tile.row, tile.col);
      if (overlay !== "selected") {
        this.setTileOverlay(tile.face, tile.row, tile.col, "hover");
      }
      // Show directional arrow when in placement mode
      if (this.placementType) {
        this.placementPreview.show(tile.face, tile.row, tile.col, this.placementOrientation);
      }
    }
  },

  // --- Cancel helpers ---

  cancelLineDraw() {
    this.lineDrawingTool.cancel(this.lineStart);
    this.lineStart = null;
  },

  cancelDemolishDraw() {
    this.demolishTool.cancel(this.demolishStart);
    this.demolishStart = null;
  },

  // --- Building render mode toggle ---

  toggleBuildingRenderMode() {
    if (this.buildingRenderMode === "3d") {
      this.buildingRenderMode = "icons";
    } else {
      this.buildingRenderMode = "3d";
    }
    this.updateAllBuildingVisibility();
    for (let faceId = 0; faceId < 30; faceId++) {
      for (let cr = 0; cr < 4; cr++) {
        for (let cc = 0; cc < 4; cc++) {
          const N = this.chunkManager.getCellLOD(faceId, cr, cc);
          if (N > 0) {
            this.regenerateCellTexture(faceId, cr, cc);
          }
        }
      }
    }
  },

  updateBuildingVisibility(faceId, cellRow, cellCol) {
    const cellKey = `${faceId}:${cellRow}:${cellCol}`;
    const buildingKeys = this.buildingsByCell.get(cellKey);
    if (!buildingKeys) return;

    const N = this.chunkManager.getCellLOD(faceId, cellRow, cellCol);
    const camDist = this.camera.position.length();

    const shouldShow = (
      this.buildingRenderMode === "3d" &&
      N >= 8 &&
      camDist < 3.5
    );

    for (const key of buildingKeys) {
      const mesh = this.buildingMeshes[key];
      if (mesh) mesh.visible = shouldShow;
    }
  },

  updateAllBuildingVisibility() {
    for (const [cellKey] of this.buildingsByCell) {
      const parts = cellKey.split(":");
      this.updateBuildingVisibility(
        parseInt(parts[0]),
        parseInt(parts[1]),
        parseInt(parts[2])
      );
    }
  },

  // --- Overlay-aware color system (delegated to ChunkManager) ---

  getTileOverlay(faceId, row, col) {
    return this.chunkManager.getTileOverlay(faceId, row, col);
  },

  setTileOverlay(faceId, row, col, overlay) {
    this.chunkManager.setTileOverlay(faceId, row, col, overlay);
  },

  // --- Camera tracking ---

  setupCameraTracking() {
    this._lastCameraPos = new THREE.Vector3();
    this._cameraTrackTimer = null;

    this._cameraTrackTimer = setInterval(() => {
      const pos = this.camera.position;
      if (!pos.equals(this._lastCameraPos)) {
        this._lastCameraPos.copy(pos);
        this.pushEvent("camera_update", {
          x: pos.x,
          y: pos.y,
          z: pos.z,
        });

        try {
          localStorage.setItem("spheric_camera_x", pos.x);
          localStorage.setItem("spheric_camera_y", pos.y);
          localStorage.setItem("spheric_camera_z", pos.z);

          // Also save full drone state for better restoration
          const droneState = this.droneCamera.getState();
          localStorage.setItem("spheric_drone_state", JSON.stringify(droneState));
        } catch (_e) { /* localStorage unavailable */ }
      }
    }, 500);
  },

  // --- Render loop ---

  animate() {
    this._animId = requestAnimationFrame(() => this.animate());

    // Update drone camera (smooth fly, height, orbit interpolation)
    const dt = 1 / 60;
    this.droneCamera.update(dt);

    // Update LOD based on camera position
    const changedCells = this.chunkManager.update(this.camera.position);
    if (changedCells.length > 0) {
      for (const { faceId, cellRow, cellCol } of changedCells) {
        this.regenerateCellTexture(faceId, cellRow, cellCol);
        this.updateBuildingVisibility(faceId, cellRow, cellCol);
      }
    }

    // Periodically sweep building visibility
    this._buildingVisFrame = (this._buildingVisFrame || 0) + 1;
    if (this._buildingVisFrame % 10 === 0) {
      this.updateAllBuildingVisibility();
    }

    // Update item positions with interpolation
    const now = performance.now();
    const interpolated = this.itemInterpolator.getInterpolatedItems(now);
    this.itemRenderer.update(interpolated);

    // Update creature positions with bobbing animation
    const deltaTime = 1 / 60;
    this.creatureRenderer.update(this.creatureData, deltaTime);

    // Atmosphere: drift dust motes
    this.atmosphere.update();

    // Altered items: pulse and rotate
    this.alteredItemRenderer.update();

    // Hiss corruption: pulse overlays and update entity positions
    this.corruptionRenderer.updateOverlays(now);
    this.corruptionRenderer.updateHissEntities();

    this.renderer.render(this.scene, this.camera);
  },

  onResize() {
    this.camera.aspect = window.innerWidth / window.innerHeight;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(window.innerWidth, window.innerHeight);
  },

  destroyed() {
    if (this._animId) cancelAnimationFrame(this._animId);
    if (this._cameraTrackTimer) clearInterval(this._cameraTrackTimer);
    window.removeEventListener("resize", this._onResize);
    window.removeEventListener("keydown", this._onKeyDown);
    this.renderer.domElement.removeEventListener("click", this._onClick);
    this.renderer.domElement.removeEventListener("mousemove", this._onMouseMove);
    this.renderer.domElement.removeEventListener("contextmenu", this._onContextMenu);

    this.placementPreview.dispose();
    this.lineDrawingTool.dispose();
    this.blueprintTool.dispose();
    this.demolishTool.dispose();

    // Dispose all building meshes
    for (const key of Object.keys(this.buildingMeshes)) {
      const mesh = this.buildingMeshes[key];
      this.scene.remove(mesh);
      this.disposeMeshGroup(mesh);
    }
    this.buildingMeshes = {};

    this.playerPresence.dispose();
    this.alteredItemRenderer.dispose();
    this.corruptionRenderer.dispose();
    this.territoryRenderer.dispose();
    this.atmosphere.dispose();
    this.droneCamera.dispose();

    if (this.itemRenderer) this.itemRenderer.dispose();
    if (this.creatureRenderer) this.creatureRenderer.dispose();
    if (this.chunkManager) this.chunkManager.dispose();
    if (this.tileTextures) this.tileTextures.dispose();
    this.renderer.dispose();
  },
};

export default GameRenderer;
