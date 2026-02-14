import * as THREE from "three";
import { TrackballControls } from "three/examples/jsm/controls/TrackballControls.js";
import { createBuildingMesh } from "../buildings/building_factory.js";
import { ItemInterpolator } from "../systems/item_interpolator.js";
import { ItemRenderer } from "../systems/item_renderer.js";
import { CreatureRenderer } from "../systems/creature_renderer.js";
import { ChunkManager } from "../systems/chunk_manager.js";
import { TileTextureGenerator } from "../systems/tile_texture.js";

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
    this.placementType = null;       // current building type being placed
    this.placementOrientation = 0;   // current placement orientation (0-3)
    this.previewArrow = null;        // arrow mesh showing output direction on hover
    this.buildingRenderMode = "3d";  // "3d" = meshes visible, "icons" = texture icons visible

    // Line-drawing mode state
    this.lineMode = false;           // toggled by L key or Line button
    this.lineStart = null;           // {face, row, col} or null — first click in line mode
    this.linePreviewTiles = [];      // [{face, row, col, orientation}, ...] for clearing overlays
    this.linePreviewMeshes = [];     // THREE.Group[] for preview arrows

    // Build face adjacency map for cross-face neighbor resolution
    this.adjacencyMap = this.buildAdjacencyMap();

    // Multiplayer: other players' markers
    this.playerMarkers = new Map(); // name -> { group, sphere, label }

    // Blueprint tool state
    this.blueprintMode = null;         // null | "capture" | "stamp"
    this.blueprintCaptureStart = null;  // {face, row, col} for capture selection
    this.blueprintPattern = null;       // [{dr, dc, type, orientation}, ...] relative offsets
    this.blueprintPreviewMeshes = [];   // THREE.Mesh[] for stamp preview
    this.savedBlueprints = this.loadBlueprints(); // [{name, pattern}, ...]

    // Spin rotation state (Ctrl+drag to spin around a point on the sphere)
    this._spinning = false;
    this._spinAxis = new THREE.Vector3();
    this._spinLastX = 0;
    this._spinVelocity = 0;
    this._suppressClick = false;
    this._spinQuat = new THREE.Quaternion();
    this._spinPointerId = null;

    this.initScene();
    this.setupSpinControl();
    this.initChunkManager();
    this.initTileTextures();
    this.setupRaycasting();
    this.setupCameraTracking();
    this.setupEventHandlers();

    // Item interpolation and rendering
    this.itemInterpolator = new ItemInterpolator();
    this.itemRenderer = new ItemRenderer(
      this.scene,
      (face, row, col) => this.getTileCenter(face, row, col)
    );

    // Creature rendering
    this.creatureRenderer = new CreatureRenderer(
      this.scene,
      (face, row, col) => this.getTileCenter(face, row, col)
    );
    this.creatureData = []; // current creature sync data for rendering

    // Altered item rendering state
    this.alteredItems = new Map(); // "face:row:col" -> { type, color }
    this.alteredMeshes = new Map(); // "face:row:col" -> THREE.Mesh
    this.alteredTime = 0;

    // Territory rendering state
    this.territoryData = new Map(); // face_id -> [{ owner_id, center_face, center_row, center_col, radius }]
    this.territoryMeshes = new Map(); // "face:row:col" -> THREE.Mesh (border overlays)

    // Hiss corruption rendering state
    this.corruptionData = new Map(); // "face:row:col" -> { intensity }
    this.corruptionMeshes = new Map(); // "face:row:col" -> THREE.Mesh
    this.hissEntityData = []; // current Hiss entity data for rendering
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
    this._corruptionGeometry = new THREE.PlaneGeometry(1, 1);

    // FBC atmosphere: floating dust motes
    this.initDustMotes();

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

    this.controls = new TrackballControls(this.camera, this.renderer.domElement);
    this.controls.noPan = true;
    this.controls.dynamicDampingFactor = 0.15;
    this.controls.minDistance = 1.08;
    this.controls.maxDistance = 8;
    this.controls.rotateSpeed = 2.0;
    this.controls.zoomSpeed = 0.4;

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

  initDustMotes() {
    const MOTE_COUNT = 200;
    const positions = new Float32Array(MOTE_COUNT * 3);
    this._moteVelocities = new Float32Array(MOTE_COUNT * 3);

    for (let i = 0; i < MOTE_COUNT; i++) {
      // Random point on sphere at height 1.03–1.06
      const theta = Math.random() * Math.PI * 2;
      const phi = Math.acos(2 * Math.random() - 1);
      const r = 1.03 + Math.random() * 0.03;
      positions[i * 3] = r * Math.sin(phi) * Math.cos(theta);
      positions[i * 3 + 1] = r * Math.sin(phi) * Math.sin(theta);
      positions[i * 3 + 2] = r * Math.cos(phi);

      // Tiny random drift velocity
      this._moteVelocities[i * 3] = (Math.random() - 0.5) * 0.0003;
      this._moteVelocities[i * 3 + 1] = (Math.random() - 0.5) * 0.0003;
      this._moteVelocities[i * 3 + 2] = (Math.random() - 0.5) * 0.0003;
    }

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.BufferAttribute(positions, 3));

    const material = new THREE.PointsMaterial({
      color: 0xccbbaa,
      size: 0.003,
      transparent: true,
      opacity: 0.25,
      sizeAttenuation: true,
      depthWrite: false,
    });

    this._dustMotes = new THREE.Points(geometry, material);
    this.scene.add(this._dustMotes);
  },

  updateDustMotes() {
    if (!this._dustMotes) return;
    const posAttr = this._dustMotes.geometry.getAttribute("position");
    const pos = posAttr.array;
    const vel = this._moteVelocities;
    const v = new THREE.Vector3();

    for (let i = 0; i < pos.length / 3; i++) {
      const ix = i * 3;
      pos[ix] += vel[ix];
      pos[ix + 1] += vel[ix + 1];
      pos[ix + 2] += vel[ix + 2];

      // Keep on sphere shell (1.03–1.06)
      v.set(pos[ix], pos[ix + 1], pos[ix + 2]);
      const r = v.length();
      if (r < 1.03 || r > 1.06) {
        v.normalize().multiplyScalar(1.03 + Math.random() * 0.03);
        pos[ix] = v.x;
        pos[ix + 1] = v.y;
        pos[ix + 2] = v.z;
      }

      // Occasionally randomize drift
      if (Math.random() < 0.002) {
        vel[ix] = (Math.random() - 0.5) * 0.0003;
        vel[ix + 1] = (Math.random() - 0.5) * 0.0003;
        vel[ix + 2] = (Math.random() - 0.5) * 0.0003;
      }
    }
    posAttr.needsUpdate = true;
  },

  initChunkManager() {
    this.chunkManager = new ChunkManager(
      this.scene,
      this.baseVertices,
      this.faceIndices,
      this.subdivisions,
      { terrainColors: TERRAIN_COLORS, resourceAccents: RESOURCE_ACCENTS }
    );
  },

  initTileTextures() {
    this.tileTextures = new TileTextureGenerator(this.subdivisions);
  },

  // --- Spin rotation (Ctrl+drag) ---

  setupSpinControl() {
    this._onSpinPointerDown = (event) => this.onSpinPointerDown(event);
    this._onSpinPointerMove = (event) => this.onSpinPointerMove(event);
    this._onSpinPointerUp = (event) => this.onSpinPointerUp(event);
    // Capture phase fires before TrackballControls' bubble-phase listener
    this.renderer.domElement.addEventListener("pointerdown", this._onSpinPointerDown, true);
  },

  onSpinPointerDown(event) {
    if (event.button !== 0 || !event.ctrlKey) return;

    // Raycast to find the sphere point under the cursor
    this.mouse.x = (event.clientX / window.innerWidth) * 2 - 1;
    this.mouse.y = -(event.clientY / window.innerHeight) * 2 + 1;
    this.raycaster.setFromCamera(this.mouse, this.camera);
    const meshes = this.chunkManager.getRaycastMeshes();
    const intersects = this.raycaster.intersectObjects(meshes);

    if (intersects.length === 0) return; // miss — let TrackballControls handle it

    // Spin axis = direction from origin through the hit point on the unit sphere
    this._spinAxis.copy(intersects[0].point).normalize();
    this._spinning = true;
    this._spinLastX = event.clientX;
    this._spinVelocity = 0;

    // Prevent TrackballControls from seeing this event
    event.stopPropagation();
    event.preventDefault();

    // Disable TrackballControls and kill any residual damping
    this.controls.enabled = false;
    this.controls._lastAngle = 0;

    // Capture pointer for reliable tracking outside the canvas
    this.renderer.domElement.setPointerCapture(event.pointerId);
    this._spinPointerId = event.pointerId;
    document.addEventListener("pointermove", this._onSpinPointerMove);
    document.addEventListener("pointerup", this._onSpinPointerUp);
  },

  onSpinPointerMove(event) {
    if (!this._spinning) return;

    const deltaX = event.clientX - this._spinLastX;
    this._spinLastX = event.clientX;

    const sensitivity = 0.005;
    const angle = deltaX * sensitivity;

    if (Math.abs(angle) > 0.0001) {
      this.applySpinRotation(angle);
      this._spinVelocity = angle;
    }
  },

  onSpinPointerUp(event) {
    if (!this._spinning) return;
    this._spinning = false;

    try {
      this.renderer.domElement.releasePointerCapture(this._spinPointerId);
    } catch (_e) { /* already released */ }

    document.removeEventListener("pointermove", this._onSpinPointerMove);
    document.removeEventListener("pointerup", this._onSpinPointerUp);

    // Re-enable TrackballControls and sync its state to the new camera position
    this.controls.enabled = true;
    this.controls._lastPosition.copy(this.camera.position);

    // Suppress the click event that fires after pointerup
    this._suppressClick = true;
    requestAnimationFrame(() => { this._suppressClick = false; });
  },

  applySpinRotation(angle) {
    this._spinQuat.setFromAxisAngle(this._spinAxis, angle);
    this.camera.position.applyQuaternion(this._spinQuat);
    this.camera.up.applyQuaternion(this._spinQuat);
    this.camera.lookAt(this.controls.target);
  },

  // --- Tile center computation (always at full resolution) ---

  getTileCenter(faceId, row, col) {
    return this.chunkManager.getTileCenter(faceId, row, col);
  },

  // --- Building placement on sphere ---

  addBuildingToScene(face, row, col, type, orientation) {
    const key = `${face}:${row}:${col}`;

    // Track building data for texture regeneration
    this.buildingData.set(key, { type, orientation });

    // Remove existing mesh if any
    if (this.buildingMeshes[key]) {
      this.scene.remove(this.buildingMeshes[key]);
    }

    const mesh = createBuildingMesh(type);
    const normal = this.getTileCenter(face, row, col).normalize();

    // Position slightly above surface
    mesh.position.copy(normal).multiplyScalar(1.005);

    // Compute forward direction from this tile toward the neighbor in the
    // orientation direction, so buildings point exactly at their output tile.
    // Use raw (unwrapped) coordinates so getTileCenter extrapolates beyond the
    // face edge correctly. Modulo wrapping would snap to the opposite edge of
    // the same face, reversing the direction for edge tiles.
    const [dr, dc] = DIR_OFFSETS[orientation];
    const neighborCenter = this.getTileCenter(face, row + dr, col + dc);

    // Project neighbor direction onto tangent plane at this tile
    const toNeighbor = new THREE.Vector3().subVectors(neighborCenter, normal);
    const tangentX = toNeighbor.addScaledVector(normal, -toNeighbor.dot(normal)).normalize();
    const tangentZ = new THREE.Vector3().crossVectors(tangentX, normal).normalize();

    const m = new THREE.Matrix4().makeBasis(tangentX, normal, tangentZ);
    mesh.quaternion.setFromRotationMatrix(m);

    mesh.visible = this.buildingRenderMode === "3d";
    this.scene.add(mesh);
    this.buildingMeshes[key] = mesh;

    // Regenerate tile texture for the affected cell
    const { cellRow, cellCol } = this.chunkManager.toCellCoords(row, col);
    this.regenerateCellTexture(face, cellRow, cellCol);
  },

  removeBuildingFromScene(face, row, col) {
    const key = `${face}:${row}:${col}`;
    const mesh = this.buildingMeshes[key];
    if (mesh) {
      this.scene.remove(mesh);
      delete this.buildingMeshes[key];
    }
    this.buildingData.delete(key);

    // Regenerate tile texture for the affected cell
    const { cellRow, cellCol } = this.chunkManager.toCellCoords(row, col);
    this.regenerateCellTexture(face, cellRow, cellCol);
  },

  /**
   * Regenerate the Canvas2D texture for a cell and apply it to the cell mesh.
   */
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
      // Rebuild any visible cells on this face now that terrain is available
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

    this.handleEvent("building_placed", ({ face, row, col, type, orientation }) => {
      this.addBuildingToScene(face, row, col, type, orientation);
    });

    this.handleEvent("building_removed", ({ face, row, col }) => {
      this.removeBuildingFromScene(face, row, col);
    });

    this.handleEvent("buildings_snapshot", ({ buildings }) => {
      for (const b of buildings) {
        this.addBuildingToScene(b.face, b.row, b.col, b.type, b.orientation);
      }
    });

    this.handleEvent("tick_items", ({ tick, face, items }) => {
      this.itemInterpolator.onTickUpdate(tick, face, items);
    });

    this.handleEvent("placement_mode", ({ type, orientation }) => {
      // Clear line-drawing state on any mode change
      this.cancelLineDraw();
      this.placementType = type;
      this.placementOrientation = orientation ?? 0;
      this.clearPreviewArrow();
      // Re-show preview if currently hovering a tile
      if (this.placementType && this.hoveredTile && !this.lineMode) {
        this.showPreviewArrow(this.hoveredTile.face, this.hoveredTile.row, this.hoveredTile.col);
      }
    });

    this.handleEvent("line_mode", ({ enabled }) => {
      this.cancelLineDraw();
      this.lineMode = enabled;
    });

    this.handleEvent("restore_player", ({ player_id, player_name, player_color, camera }) => {
      // Persist identity to localStorage so it survives reconnects
      try {
        localStorage.setItem("spheric_player_id", player_id);
        localStorage.setItem("spheric_player_name", player_name);
        localStorage.setItem("spheric_player_color", player_color);
      } catch (_e) { /* localStorage unavailable */ }

      // Restore camera position (target is always origin for sphere viewing)
      if (camera && camera.z != null) {
        this.camera.position.set(camera.x, camera.y, camera.z);
        this.controls.update();
      }
    });

    this.handleEvent("save_hotbar", ({ hotbar }) => {
      try {
        localStorage.setItem("spheric_hotbar", JSON.stringify(hotbar));
      } catch (_e) { /* localStorage unavailable */ }
    });

    this.handleEvent("players_update", ({ players }) => {
      this.updatePlayerMarkers(players);
    });

    this.handleEvent("place_error", ({ face, row, col, reason }) => {
      // Brief red flash on the tile via overlay
      this.setTileOverlay(face, row, col, "error");
      setTimeout(() => {
        // Restore to whatever it was before (selected or nothing)
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
      // Replace creature data for this face
      this.creatureData = this.creatureData.filter(c => c.face !== face);
      this.creatureData.push(...creatures);
    });

    this.handleEvent("creature_spawned", ({ id, creature }) => {
      this.creatureRenderer.onCreatureSpawned(id, creature);
      this.creatureData.push({ id, ...creature });
    });

    this.handleEvent("creature_moved", ({ id, creature }) => {
      this.creatureRenderer.onCreatureMoved(id, creature);
      // Update local data
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
        this.addAlteredItemMesh(face, item.row, item.col, item.type, item.color);
      }
    });

    // --- Hiss Corruption ---

    this.handleEvent("corruption_sync", ({ face, tiles }) => {
      // Remove old corruption meshes for this face
      for (const [key, mesh] of this.corruptionMeshes) {
        if (key.startsWith(`${face}:`)) {
          this.scene.remove(mesh);
          this.corruptionMeshes.delete(key);
          this.corruptionData.delete(key);
        }
      }
      // Add current corruption
      for (const tile of tiles) {
        this.addCorruptionOverlay(tile.face, tile.row, tile.col, tile.intensity);
      }
    });

    this.handleEvent("corruption_update", ({ face, tiles }) => {
      for (const tile of tiles) {
        this.addCorruptionOverlay(tile.face, tile.row, tile.col, tile.intensity);
      }
    });

    this.handleEvent("corruption_cleared", ({ face, tiles }) => {
      for (const tile of tiles) {
        this.removeCorruptionOverlay(tile.face, tile.row, tile.col);
      }
    });

    // --- Territory ---

    this.handleEvent("territory_update", ({ face, territories }) => {
      this.territoryData.set(face, territories);
      this.rebuildTerritoryOverlays(face);
    });

    this.handleEvent("territory_sync", ({ face, territories }) => {
      this.territoryData.set(face, territories);
      this.rebuildTerritoryOverlays(face);
    });

    this.handleEvent("hiss_sync", ({ face, entities }) => {
      // Remove old Hiss meshes for this face
      for (const [id, mesh] of this.hissEntityMeshes) {
        const data = this.hissEntityData.find(e => e.id === id);
        if (data && data.face === face) {
          this.scene.remove(mesh);
          mesh.geometry.dispose();
          mesh.material.dispose();
          this.hissEntityMeshes.delete(id);
        }
      }
      this.hissEntityData = this.hissEntityData.filter(e => e.face !== face);
      this.hissEntityData.push(...entities);
    });

    this.handleEvent("hiss_spawned", ({ id, entity }) => {
      this.hissEntityData.push({ id, ...entity });
    });

    this.handleEvent("hiss_moved", ({ id, entity }) => {
      const idx = this.hissEntityData.findIndex(e => e.id === id);
      if (idx >= 0) {
        this.hissEntityData[idx] = { id, ...entity };
      } else {
        this.hissEntityData.push({ id, ...entity });
      }
    });

    this.handleEvent("hiss_killed", ({ id }) => {
      this.hissEntityData = this.hissEntityData.filter(e => e.id !== id);
      const mesh = this.hissEntityMeshes.get(id);
      if (mesh) {
        this.scene.remove(mesh);
        mesh.geometry.dispose();
        mesh.material.dispose();
        this.hissEntityMeshes.delete(id);
      }
    });

    this.handleEvent("building_damaged", ({ face, row, col, action }) => {
      // Flash the tile red briefly
      this.setTileOverlay(face, row, col, "error");
      setTimeout(() => {
        this.setTileOverlay(face, row, col, null);
      }, 200);
    });

    // Blueprint tool events from LiveView
    this.handleEvent("blueprint_mode", ({ mode }) => {
      this.cancelLineDraw();
      this.clearPreviewArrow();
      this.clearBlueprintPreview();
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
      const bp = this.savedBlueprints[index];
      if (bp) {
        this.blueprintPattern = bp.pattern;
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
      // Store active event for potential visual effects
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
          this.clearBlueprintPreview();
          this.blueprintMode = null;
          this.blueprintCaptureStart = null;
          this.pushEvent("blueprint_cancelled", {});
          return;
        }
        if (this.lineStart) {
          this.cancelLineDraw();
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
    if (this._suppressClick) return;
    const tile = this.hitToTile(event);
    if (!tile) return;

    // Blueprint mode: capture or stamp
    if (this.blueprintMode) {
      if (this.onBlueprintClick(tile)) return;
    }

    // Line-drawing mode: two-click workflow
    if (this.lineMode && this.placementType) {
      if (!this.lineStart) {
        // First click: set start tile
        this.lineStart = tile;
        this.setTileOverlay(tile.face, tile.row, tile.col, "selected");
        return;
      } else {
        // Second click: compute path and send batch placement
        const path = this.computeLinePath(this.lineStart, tile);
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

    // Send to server — server decides whether this is a selection or building placement
    this.pushEvent("tile_click", {
      face: tile.face,
      row: tile.row,
      col: tile.col,
    });
  },

  onTileRightClick(event) {
    event.preventDefault();
    if (this._spinning) return;

    // Cancel line-drawing if active
    if (this.lineStart) {
      this.cancelLineDraw();
      return;
    }

    const tile = this.hitToTile(event);
    if (!tile) return;

    this.pushEvent("remove_building", {
      face: tile.face,
      row: tile.row,
      col: tile.col,
    });
  },

  onTileHover(event) {
    if (this._spinning) return;
    const tile = this.hitToTile(event);

    // Clear previous hover
    if (this.hoveredTile) {
      const h = this.hoveredTile;
      const overlay = this.getTileOverlay(h.face, h.row, h.col);
      if (overlay === "hover") {
        this.setTileOverlay(h.face, h.row, h.col, null);
      }
    }

    this.clearPreviewArrow();
    this.hoveredTile = tile;

    if (tile) {
      // Blueprint stamp preview
      if (this.blueprintMode === "stamp" && this.blueprintPattern) {
        this.showBlueprintPreview(tile);
        return;
      }

      // If in line-drawing mode with start set, show line preview
      if (this.lineMode && this.lineStart) {
        this.showLinePreview(tile);
        return;
      }

      const overlay = this.getTileOverlay(tile.face, tile.row, tile.col);
      if (overlay !== "selected") {
        this.setTileOverlay(tile.face, tile.row, tile.col, "hover");
      }
      // Show directional arrow when in placement mode
      if (this.placementType) {
        this.showPreviewArrow(tile.face, tile.row, tile.col);
      }
    }
  },

  // --- Placement preview arrow ---

  showPreviewArrow(face, row, col) {
    const N = this.subdivisions;
    const orientation = this.placementOrientation;
    const [dr, dc] = DIR_OFFSETS[orientation];

    const from = this.getTileCenter(face, row, col);
    // Use raw coordinates (no modulo) so edge tiles point in the correct direction
    const to = this.getTileCenter(face, row + dr, col + dc);
    const normal = from.clone().normalize();

    // Build arrow from tile center toward neighbor, on the surface
    const dir = new THREE.Vector3().subVectors(to, from);
    dir.addScaledVector(normal, -dir.dot(normal)).normalize();

    const LIFT = 1.018;
    const LEN = 0.6 / N;  // arrow length relative to tile size
    const start = from.clone().multiplyScalar(LIFT);
    const end = start.clone().addScaledVector(dir, LEN);

    // Shaft
    const shaftGeo = new THREE.BufferGeometry().setFromPoints([start, end]);
    const shaftMat = new THREE.LineBasicMaterial({ color: 0xffdd44, linewidth: 2 });
    const shaft = new THREE.Line(shaftGeo, shaftMat);

    // Arrowhead (small cone at the tip)
    const cone = new THREE.Mesh(
      new THREE.ConeGeometry(0.002, 0.005, 6),
      new THREE.MeshBasicMaterial({ color: 0xffdd44 })
    );
    cone.position.copy(end);
    // Orient cone along dir, with default cone axis = +Y
    const up = new THREE.Vector3(0, 1, 0);
    cone.quaternion.setFromUnitVectors(up, dir);

    const group = new THREE.Group();
    group.add(shaft);
    group.add(cone);
    this.scene.add(group);
    this.previewArrow = group;
  },

  clearPreviewArrow() {
    if (this.previewArrow) {
      this.scene.remove(this.previewArrow);
      this.previewArrow = null;
    }
  },

  // --- Line-drawing mode ---

  buildAdjacencyMap() {
    const faces = this.faceIndices;
    const edgeToFaces = new Map();

    for (let faceId = 0; faceId < faces.length; faceId++) {
      const [v0, v1, v2, v3] = faces[faceId];
      const edges = [[v0, v1], [v1, v2], [v2, v3], [v3, v0]];

      for (let edgeIdx = 0; edgeIdx < 4; edgeIdx++) {
        const [a, b] = edges[edgeIdx];
        const edgeKey = Math.min(a, b) * 10000 + Math.max(a, b);
        if (!edgeToFaces.has(edgeKey)) edgeToFaces.set(edgeKey, []);
        edgeToFaces.get(edgeKey).push({ faceId, edgeIdx, verts: [a, b] });
      }
    }

    const adjacency = [];
    for (let faceId = 0; faceId < faces.length; faceId++) {
      const [v0, v1, v2, v3] = faces[faceId];
      const edges = [[v0, v1], [v1, v2], [v2, v3], [v3, v0]];
      const neighbors = [];

      for (let edgeIdx = 0; edgeIdx < 4; edgeIdx++) {
        const [a, b] = edges[edgeIdx];
        const edgeKey = Math.min(a, b) * 10000 + Math.max(a, b);
        const entries = edgeToFaces.get(edgeKey);
        const other = entries.find(e => e.faceId !== faceId);

        if (other) {
          const theirVerts = other.verts;
          const flipped = (a === theirVerts[1] && b === theirVerts[0]);
          neighbors.push({ face: other.faceId, theirEdge: other.edgeIdx, flipped });
        } else {
          neighbors.push(null);
        }
      }
      adjacency.push(neighbors);
    }
    return adjacency;
  },

  getNeighborTile(tile, direction) {
    const N = this.subdivisions;
    const { face, row, col } = tile;
    const [dr, dc] = DIR_OFFSETS[direction];
    const newRow = row + dr;
    const newCol = col + dc;

    if (newRow >= 0 && newRow < N && newCol >= 0 && newCol < N) {
      return { face, row: newRow, col: newCol };
    }
    return this.crossFaceNeighbor(face, row, col, direction);
  },

  crossFaceNeighbor(face, row, col, direction) {
    const max = this.subdivisions - 1;

    let myEdge, posAlongEdge;
    switch (direction) {
      case 0: myEdge = 1; posAlongEdge = row; break;
      case 1: myEdge = 2; posAlongEdge = max - col; break;
      case 2: myEdge = 3; posAlongEdge = max - row; break;
      case 3: myEdge = 0; posAlongEdge = col; break;
    }

    const neighborInfo = this.adjacencyMap[face][myEdge];
    if (!neighborInfo) return null;

    const pos = neighborInfo.flipped ? max - posAlongEdge : posAlongEdge;

    let newRow, newCol;
    switch (neighborInfo.theirEdge) {
      case 0: newRow = 0; newCol = pos; break;
      case 1: newRow = pos; newCol = max; break;
      case 2: newRow = max; newCol = max - pos; break;
      case 3: newRow = max - pos; newCol = 0; break;
    }

    return { face: neighborInfo.face, row: newRow, col: newCol };
  },

  bestDirectionToward(tile, targetPos) {
    let bestDir = 0;
    let bestDist = Infinity;

    for (let dir = 0; dir < 4; dir++) {
      const [dr, dc] = DIR_OFFSETS[dir];
      const neighborPos = this.getTileCenter(tile.face, tile.row + dr, tile.col + dc);
      const dist = neighborPos.distanceToSquared(targetPos);
      if (dist < bestDist) {
        bestDist = dist;
        bestDir = dir;
      }
    }
    return bestDir;
  },

  computeLinePath(start, end) {
    const MAX_LINE_LENGTH = 128;
    const path = [];
    const visited = new Set();

    let current = { face: start.face, row: start.row, col: start.col };
    const targetPos = this.getTileCenter(end.face, end.row, end.col);

    // Special case: start == end, place single tile with current orientation
    if (start.face === end.face && start.row === end.row && start.col === end.col) {
      return [{ ...current, orientation: this.placementOrientation }];
    }

    for (let step = 0; step < MAX_LINE_LENGTH; step++) {
      const key = `${current.face}:${current.row}:${current.col}`;
      if (visited.has(key)) break;
      visited.add(key);

      const isTarget =
        current.face === end.face &&
        current.row === end.row &&
        current.col === end.col;

      if (isTarget) {
        // Last tile gets same orientation as previous
        const prevOrientation = path.length > 0
          ? path[path.length - 1].orientation
          : this.placementOrientation;
        path.push({ ...current, orientation: prevOrientation });
        break;
      }

      const bestDir = this.bestDirectionToward(current, targetPos);
      path.push({ ...current, orientation: bestDir });

      const neighbor = this.getNeighborTile(current, bestDir);
      if (!neighbor) break;
      current = neighbor;
    }

    return path;
  },

  showLinePreview(endTile) {
    this.clearLinePreview();

    const path = this.computeLinePath(this.lineStart, endTile);
    this.linePreviewTiles = path;

    for (const tile of path) {
      this.setTileOverlay(tile.face, tile.row, tile.col, "hover");
      this.showPreviewArrowAt(tile.face, tile.row, tile.col, tile.orientation);
    }
  },

  showPreviewArrowAt(face, row, col, orientation) {
    const N = this.subdivisions;
    const [dr, dc] = DIR_OFFSETS[orientation];

    const from = this.getTileCenter(face, row, col);
    const to = this.getTileCenter(face, row + dr, col + dc);
    const normal = from.clone().normalize();

    const dir = new THREE.Vector3().subVectors(to, from);
    dir.addScaledVector(normal, -dir.dot(normal)).normalize();

    const LIFT = 1.018;
    const LEN = 0.6 / N;
    const start = from.clone().multiplyScalar(LIFT);
    const end = start.clone().addScaledVector(dir, LEN);

    const shaftGeo = new THREE.BufferGeometry().setFromPoints([start, end]);
    const shaftMat = new THREE.LineBasicMaterial({ color: 0x44ddff, linewidth: 2 });
    const shaft = new THREE.Line(shaftGeo, shaftMat);

    const cone = new THREE.Mesh(
      new THREE.ConeGeometry(0.002, 0.005, 6),
      new THREE.MeshBasicMaterial({ color: 0x44ddff })
    );
    cone.position.copy(end);
    cone.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir);

    const group = new THREE.Group();
    group.add(shaft);
    group.add(cone);
    this.scene.add(group);
    this.linePreviewMeshes.push(group);
  },

  clearLinePreview() {
    for (const group of this.linePreviewMeshes) {
      this.scene.remove(group);
    }
    this.linePreviewMeshes = [];

    for (const tile of this.linePreviewTiles) {
      const overlay = this.getTileOverlay(tile.face, tile.row, tile.col);
      if (overlay === "hover") {
        this.setTileOverlay(tile.face, tile.row, tile.col, null);
      }
    }
    this.linePreviewTiles = [];
  },

  cancelLineDraw() {
    this.clearLinePreview();
    if (this.lineStart) {
      const overlay = this.getTileOverlay(this.lineStart.face, this.lineStart.row, this.lineStart.col);
      if (overlay === "selected") {
        this.setTileOverlay(this.lineStart.face, this.lineStart.row, this.lineStart.col, null);
      }
      this.lineStart = null;
    }
  },

  // --- Blueprint tool ---

  loadBlueprints() {
    try {
      const raw = localStorage.getItem("spheric_blueprints");
      return raw ? JSON.parse(raw) : [];
    } catch (_e) {
      return [];
    }
  },

  saveBlueprints() {
    try {
      localStorage.setItem("spheric_blueprints", JSON.stringify(this.savedBlueprints));
    } catch (_e) { /* localStorage unavailable */ }
  },

  onBlueprintClick(tile) {
    if (this.blueprintMode === "capture") {
      this.handleBlueprintCapture(tile);
      return true;
    }
    if (this.blueprintMode === "stamp" && this.blueprintPattern) {
      this.handleBlueprintStamp(tile);
      return true;
    }
    return false;
  },

  handleBlueprintCapture(tile) {
    if (!this.blueprintCaptureStart) {
      // First click: set capture origin
      this.blueprintCaptureStart = tile;
      this.setTileOverlay(tile.face, tile.row, tile.col, "selected");
      return;
    }

    // Second click: capture rectangle on same face
    const start = this.blueprintCaptureStart;
    if (start.face !== tile.face) {
      // Cross-face capture not supported, reset
      this.setTileOverlay(start.face, start.row, start.col, null);
      this.blueprintCaptureStart = null;
      return;
    }

    const minRow = Math.min(start.row, tile.row);
    const maxRow = Math.max(start.row, tile.row);
    const minCol = Math.min(start.col, tile.col);
    const maxCol = Math.max(start.col, tile.col);

    // Extract buildings in the rectangle
    const pattern = [];
    for (let r = minRow; r <= maxRow; r++) {
      for (let c = minCol; c <= maxCol; c++) {
        const key = `${start.face}:${r}:${c}`;
        const data = this.buildingData.get(key);
        if (data) {
          pattern.push({
            dr: r - minRow,
            dc: c - minCol,
            type: data.type,
            orientation: data.orientation,
          });
        }
      }
    }

    // Clear capture overlay
    this.setTileOverlay(start.face, start.row, start.col, null);
    this.blueprintCaptureStart = null;

    if (pattern.length === 0) {
      return;
    }

    this.blueprintPattern = pattern;

    // Save blueprint with auto-generated name
    const name = `Blueprint ${this.savedBlueprints.length + 1} (${pattern.length} buildings)`;
    this.savedBlueprints.push({ name, pattern });
    this.saveBlueprints();

    // Notify LiveView to update blueprint list
    this.pushEvent("blueprint_captured", {
      name,
      count: pattern.length,
      index: this.savedBlueprints.length - 1,
    });

    // Switch to stamp mode
    this.blueprintMode = "stamp";
  },

  handleBlueprintStamp(tile) {
    const pattern = this.blueprintPattern;
    if (!pattern || pattern.length === 0) return;

    // Map relative offsets to absolute tile positions from the click point
    const buildings = [];
    for (const entry of pattern) {
      // Walk from origin tile by dr rows and dc cols using neighbor resolution
      let current = { face: tile.face, row: tile.row, col: tile.col };

      // Move by dr rows (direction 1 = +row)
      for (let i = 0; i < entry.dr; i++) {
        const next = this.getNeighborTile(current, 1);
        if (!next) { current = null; break; }
        current = next;
      }
      if (!current) continue;

      // Move by dc cols (direction 0 = +col)
      for (let i = 0; i < entry.dc; i++) {
        const next = this.getNeighborTile(current, 0);
        if (!next) { current = null; break; }
        current = next;
      }
      if (!current) continue;

      buildings.push({
        face: current.face,
        row: current.row,
        col: current.col,
        orientation: entry.orientation,
        type: entry.type,
      });
    }

    if (buildings.length > 0) {
      // Set placement type temporarily for the batch to work
      this.pushEvent("place_blueprint", { buildings });
    }
  },

  showBlueprintPreview(tile) {
    this.clearBlueprintPreview();
    if (!this.blueprintPattern) return;

    for (const entry of this.blueprintPattern) {
      let current = { face: tile.face, row: tile.row, col: tile.col };

      for (let i = 0; i < entry.dr; i++) {
        const next = this.getNeighborTile(current, 1);
        if (!next) { current = null; break; }
        current = next;
      }
      if (!current) continue;

      for (let i = 0; i < entry.dc; i++) {
        const next = this.getNeighborTile(current, 0);
        if (!next) { current = null; break; }
        current = next;
      }
      if (!current) continue;

      this.setTileOverlay(current.face, current.row, current.col, "hover");
      this.blueprintPreviewMeshes.push(current);
    }
  },

  clearBlueprintPreview() {
    for (const tile of this.blueprintPreviewMeshes) {
      const overlay = this.getTileOverlay(tile.face, tile.row, tile.col);
      if (overlay === "hover") {
        this.setTileOverlay(tile.face, tile.row, tile.col, null);
      }
    }
    this.blueprintPreviewMeshes = [];
  },

  deleteBlueprint(index) {
    if (index >= 0 && index < this.savedBlueprints.length) {
      this.savedBlueprints.splice(index, 1);
      this.saveBlueprints();
    }
  },

  // --- Building render mode toggle ---

  toggleBuildingRenderMode() {
    if (this.buildingRenderMode === "3d") {
      this.buildingRenderMode = "icons";
      // Hide all 3D meshes
      for (const key of Object.keys(this.buildingMeshes)) {
        this.buildingMeshes[key].visible = false;
      }
    } else {
      this.buildingRenderMode = "3d";
      // Show all 3D meshes
      for (const key of Object.keys(this.buildingMeshes)) {
        this.buildingMeshes[key].visible = true;
      }
    }
    // Regenerate textures so icons appear/disappear
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

        // Persist camera state to localStorage for reconnect restoration
        try {
          localStorage.setItem("spheric_camera_x", pos.x);
          localStorage.setItem("spheric_camera_y", pos.y);
          localStorage.setItem("spheric_camera_z", pos.z);
        } catch (_e) { /* localStorage unavailable */ }
      }
    }, 500);
  },

  // --- Render loop ---

  animate() {
    this._animId = requestAnimationFrame(() => this.animate());

    // Spin damping: coast to a stop after Ctrl+drag release
    if (!this._spinning && Math.abs(this._spinVelocity) > 0.0001) {
      this.applySpinRotation(this._spinVelocity);
      this._spinVelocity *= (1.0 - this.controls.dynamicDampingFactor);
      if (Math.abs(this._spinVelocity) < 0.00005) {
        this._spinVelocity = 0;
      }
    }

    // Scale rotate and zoom speed with camera distance so close-up controls aren't too fast
    const dist = this.camera.position.length();
    this.controls.rotateSpeed = 0.25 + Math.min((dist - 1.0) / 2.5, 1.0);
    this.controls.zoomSpeed = 0.1 + 0.3 * Math.min((dist - 1.0) / 2.0, 1.0);

    this.controls.update();

    // Update LOD based on camera position (ChunkManager handles dirty checks)
    const changedCells = this.chunkManager.update(this.camera.position);
    if (changedCells.length > 0) {
      // Regenerate textures only for cells that changed LOD
      for (const { faceId, cellRow, cellCol } of changedCells) {
        this.regenerateCellTexture(faceId, cellRow, cellCol);
      }
    }

    // Update item positions with interpolation
    const now = performance.now();
    const interpolated = this.itemInterpolator.getInterpolatedItems(now);
    this.itemRenderer.update(interpolated);

    // Update creature positions with bobbing animation
    const deltaTime = 1 / 60; // approximate frame time
    this.creatureRenderer.update(this.creatureData, deltaTime);

    // FBC atmosphere: drift dust motes
    this.updateDustMotes();

    // Altered items: pulse and rotate
    this.updateAlteredItems(now);

    // Hiss corruption: pulse overlays and update entity positions
    this.updateCorruptionOverlays(now);
    this.updateHissEntities();

    this.renderer.render(this.scene, this.camera);
  },

  // --- Multiplayer player markers ---

  updatePlayerMarkers(players) {
    const activeNames = new Set();

    for (const p of players) {
      activeNames.add(p.name);
      const cameraPos = new THREE.Vector3(p.x, p.y, p.z);

      // Compute surface point: normalize camera direction to get point on sphere
      const surfacePoint = cameraPos.clone().normalize();

      let marker = this.playerMarkers.get(p.name);
      if (!marker) {
        marker = this.createPlayerMarker(p.name, p.color);
        this.playerMarkers.set(p.name, marker);
        this.scene.add(marker.group);
      }

      // Position marker slightly above sphere surface
      marker.group.position.copy(surfacePoint).multiplyScalar(1.01);

      // Orient label to face outward from sphere center
      marker.group.lookAt(surfacePoint.clone().multiplyScalar(2));
    }

    // Remove markers for players who left
    for (const [name, marker] of this.playerMarkers) {
      if (!activeNames.has(name)) {
        this.scene.remove(marker.group);
        marker.label.material.map.dispose();
        marker.label.material.dispose();
        marker.sphere.material.dispose();
        marker.sphere.geometry.dispose();
        this.playerMarkers.delete(name);
      }
    }
  },

  createPlayerMarker(name, color) {
    const group = new THREE.Group();

    // Small sphere marker
    const sphereGeo = new THREE.SphereGeometry(0.006, 8, 8);
    const sphereMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(color) });
    const sphere = new THREE.Mesh(sphereGeo, sphereMat);
    group.add(sphere);

    // Text label sprite
    const canvas = document.createElement("canvas");
    canvas.width = 128;
    canvas.height = 32;
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = color;
    ctx.font = "bold 18px monospace";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(name, 64, 16);

    const texture = new THREE.CanvasTexture(canvas);
    texture.minFilter = THREE.LinearFilter;
    const spriteMat = new THREE.SpriteMaterial({ map: texture, transparent: true });
    const label = new THREE.Sprite(spriteMat);
    label.scale.set(0.03, 0.008, 1);
    label.position.set(0, 0.01, 0);
    group.add(label);

    return { group, sphere, label };
  },

  disposePlayerMarkers() {
    for (const [, marker] of this.playerMarkers) {
      this.scene.remove(marker.group);
      marker.label.material.map.dispose();
      marker.label.material.dispose();
      marker.sphere.material.dispose();
      marker.sphere.geometry.dispose();
    }
    this.playerMarkers.clear();
  },

  // --- Altered Items rendering ---

  updateAlteredItems(now) {
    this.alteredTime += 0.016;
    for (const [key, mesh] of this.alteredMeshes) {
      const item = this.alteredItems.get(key);
      if (!item || !mesh) continue;
      // Gentle rotation
      mesh.rotation.x += 0.01;
      mesh.rotation.y += 0.015;
      // Pulse emissive intensity
      const pulse = 0.4 + 0.6 * Math.sin(this.alteredTime * 2.0 + mesh.userData.phase);
      mesh.material.emissiveIntensity = pulse;
    }
  },

  addAlteredItemMesh(face, row, col, type, colorHex) {
    const key = `${face}:${row}:${col}`;
    if (this.alteredMeshes.has(key)) return;

    const center = this.getTileCenter(face, row, col);
    if (!center) return;

    const geo = new THREE.OctahedronGeometry(0.005, 0);
    const mat = new THREE.MeshStandardMaterial({
      color: colorHex,
      emissive: colorHex,
      emissiveIntensity: 0.5,
      transparent: true,
      opacity: 0.85,
      metalness: 0.3,
      roughness: 0.4,
    });

    const mesh = new THREE.Mesh(geo, mat);
    const pos = center.clone().normalize().multiplyScalar(1.01);
    mesh.position.copy(pos);
    mesh.userData.phase = Math.random() * Math.PI * 2;
    this.scene.add(mesh);
    this.alteredMeshes.set(key, mesh);
    this.alteredItems.set(key, { type, color: colorHex });
  },

  removeAlteredItemMesh(face, row, col) {
    const key = `${face}:${row}:${col}`;
    const mesh = this.alteredMeshes.get(key);
    if (mesh) {
      this.scene.remove(mesh);
      mesh.geometry.dispose();
      mesh.material.dispose();
      this.alteredMeshes.delete(key);
    }
    this.alteredItems.delete(key);
  },

  disposeAlteredItems() {
    for (const [, mesh] of this.alteredMeshes) {
      this.scene.remove(mesh);
      mesh.geometry.dispose();
      mesh.material.dispose();
    }
    this.alteredMeshes.clear();
    this.alteredItems.clear();
  },

  // --- Hiss Corruption Rendering ---

  addCorruptionOverlay(face, row, col, intensity) {
    const key = `${face}:${row}:${col}`;
    this.corruptionData.set(key, { intensity });

    // Remove existing mesh if any
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

    // Orient plane to face outward from sphere
    mesh.quaternion.setFromUnitVectors(
      new THREE.Vector3(0, 0, 1), normal
    );

    mesh.userData.intensity = intensity;
    mesh.userData.phase = Math.random() * Math.PI * 2;
    this.scene.add(mesh);
    this.corruptionMeshes.set(key, mesh);
  },

  rebuildTerritoryOverlays(faceId) {
    // Remove existing territory meshes for this face
    for (const [key, mesh] of this.territoryMeshes) {
      if (key.startsWith(`${faceId}:`)) {
        this.scene.remove(mesh);
        mesh.geometry.dispose();
        mesh.material.dispose();
        this.territoryMeshes.delete(key);
      }
    }

    const territories = this.territoryData.get(faceId);
    if (!territories || territories.length === 0) return;

    const N = this.subdivisions;

    // For each territory on this face, draw border tiles
    for (const t of territories) {
      const r = t.radius;
      // Hash owner_id to a color
      const color = this.ownerIdToColor(t.owner_id);

      // Draw only the border tiles (edges of the radius box)
      for (let row = t.center_row - r; row <= t.center_row + r; row++) {
        for (let col = t.center_col - r; col <= t.center_col + r; col++) {
          if (row < 0 || row >= N || col < 0 || col >= N) continue;

          // Only draw if on the border (edge of the claimed rectangle)
          const onBorder =
            row === t.center_row - r || row === t.center_row + r ||
            col === t.center_col - r || col === t.center_col + r;
          if (!onBorder) continue;

          const key = `${faceId}:${row}:${col}`;
          if (this.territoryMeshes.has(key)) continue;

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
          this.territoryMeshes.set(key, mesh);
        }
      }
    }
  },

  ownerIdToColor(ownerId) {
    // Simple hash to generate a consistent color per player
    let hash = 0;
    for (let i = 0; i < ownerId.length; i++) {
      hash = ((hash << 5) - hash) + ownerId.charCodeAt(i);
      hash |= 0;
    }
    const hue = Math.abs(hash % 360);
    return new THREE.Color(`hsl(${hue}, 60%, 50%)`);
  },

  removeCorruptionOverlay(face, row, col) {
    const key = `${face}:${row}:${col}`;
    const mesh = this.corruptionMeshes.get(key);
    if (mesh) {
      this.scene.remove(mesh);
      mesh.geometry.dispose();
      mesh.material.dispose();
      this.corruptionMeshes.delete(key);
    }
    this.corruptionData.delete(key);
  },

  updateCorruptionOverlays(now) {
    const t = now * 0.001;
    for (const [, mesh] of this.corruptionMeshes) {
      // Pulsing opacity based on intensity
      const intensity = mesh.userData.intensity || 1;
      const baseAlpha = 0.15 + (intensity / 10) * 0.45;
      const pulse = 0.8 + 0.2 * Math.sin(t * 3.0 + mesh.userData.phase);
      mesh.material.opacity = baseAlpha * pulse;
    }
  },

  updateHissEntities() {
    // Ensure meshes exist for all Hiss entities and update positions
    for (const entity of this.hissEntityData) {
      let mesh = this.hissEntityMeshes.get(entity.id);
      if (!mesh) {
        mesh = new THREE.Mesh(
          this._hissGeometry.clone(),
          this._hissMaterial.clone()
        );
        this.scene.add(mesh);
        this.hissEntityMeshes.set(entity.id, mesh);
      }

      const center = this.getTileCenter(entity.face, entity.row, entity.col);
      if (center) {
        const target = center.clone().normalize().multiplyScalar(1.012);
        // Lerp position for smooth movement
        mesh.position.lerp(target, 0.15);
      }

      // Rotate and bob
      mesh.rotation.x += 0.03;
      mesh.rotation.y += 0.02;
    }

    // Remove meshes for entities that no longer exist
    const activeIds = new Set(this.hissEntityData.map(e => e.id));
    for (const [id, mesh] of this.hissEntityMeshes) {
      if (!activeIds.has(id)) {
        this.scene.remove(mesh);
        mesh.geometry.dispose();
        mesh.material.dispose();
        this.hissEntityMeshes.delete(id);
      }
    }
  },

  disposeTerritory() {
    for (const [, mesh] of this.territoryMeshes) {
      this.scene.remove(mesh);
      mesh.geometry.dispose();
      mesh.material.dispose();
    }
    this.territoryMeshes.clear();
    this.territoryData.clear();
  },

  disposeCorruption() {
    for (const [, mesh] of this.corruptionMeshes) {
      this.scene.remove(mesh);
      mesh.geometry.dispose();
      mesh.material.dispose();
    }
    this.corruptionMeshes.clear();
    this.corruptionData.clear();

    for (const [, mesh] of this.hissEntityMeshes) {
      this.scene.remove(mesh);
      mesh.geometry.dispose();
      mesh.material.dispose();
    }
    this.hissEntityMeshes.clear();
    this.hissEntityData = [];
  },

  onResize() {
    this.camera.aspect = window.innerWidth / window.innerHeight;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    this.controls.handleResize();
  },

  destroyed() {
    if (this._animId) cancelAnimationFrame(this._animId);
    if (this._cameraTrackTimer) clearInterval(this._cameraTrackTimer);
    window.removeEventListener("resize", this._onResize);
    window.removeEventListener("keydown", this._onKeyDown);
    this.renderer.domElement.removeEventListener("pointerdown", this._onSpinPointerDown, true);
    document.removeEventListener("pointermove", this._onSpinPointerMove);
    document.removeEventListener("pointerup", this._onSpinPointerUp);
    this.renderer.domElement.removeEventListener("click", this._onClick);
    this.renderer.domElement.removeEventListener("mousemove", this._onMouseMove);
    this.renderer.domElement.removeEventListener("contextmenu", this._onContextMenu);
    this.clearPreviewArrow();
    this.clearLinePreview();
    this.clearBlueprintPreview();
    this.disposePlayerMarkers();
    this.disposeAlteredItems();
    this.disposeCorruption();
    if (this._dustMotes) {
      this.scene.remove(this._dustMotes);
      this._dustMotes.geometry.dispose();
      this._dustMotes.material.dispose();
    }
    if (this.itemRenderer) this.itemRenderer.dispose();
    if (this.creatureRenderer) this.creatureRenderer.dispose();
    if (this.chunkManager) this.chunkManager.dispose();
    if (this.tileTextures) this.tileTextures.dispose();
    this.controls.dispose();
    this.renderer.dispose();
  },
};

export default GameRenderer;
