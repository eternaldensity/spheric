import * as THREE from "three";
import { TrackballControls } from "three/examples/jsm/controls/TrackballControls.js";
import { createBuildingMesh } from "../buildings/building_factory.js";
import { ItemInterpolator } from "../systems/item_interpolator.js";
import { ItemRenderer } from "../systems/item_renderer.js";
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

    // Do initial LOD update with starting camera position
    this.chunkManager.update(this.camera.position);

    this.animate();

    this._onResize = () => this.onResize();
    window.addEventListener("resize", this._onResize);
  },

  initScene() {
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x0a0a1a);

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

    // Lighting
    this.scene.add(new THREE.AmbientLight(0x606070, 1.5));
    const dirLight = new THREE.DirectionalLight(0xffffff, 1.0);
    dirLight.position.set(5, 3, 4);
    this.scene.add(dirLight);
    const fillLight = new THREE.DirectionalLight(0x8888ff, 0.3);
    fillLight.position.set(-3, -2, -4);
    this.scene.add(fillLight);
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
      if (event.key === "Escape" && this.lineStart) {
        this.cancelLineDraw();
        return;
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
      marker.group.position.copy(surfacePoint).multiplyScalar(1.02);

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
    const sphereGeo = new THREE.SphereGeometry(0.025, 8, 8);
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
    label.scale.set(0.12, 0.03, 1);
    label.position.set(0, 0.04, 0);
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
    this.disposePlayerMarkers();
    if (this.itemRenderer) this.itemRenderer.dispose();
    if (this.chunkManager) this.chunkManager.dispose();
    if (this.tileTextures) this.tileTextures.dispose();
    this.controls.dispose();
    this.renderer.dispose();
  },
};

export default GameRenderer;
