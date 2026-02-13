import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
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

    // Parse terrain data
    this.terrainData = JSON.parse(this.el.dataset.terrain);

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

    // Multiplayer: other players' markers
    this.playerMarkers = new Map(); // name -> { group, sphere, label }

    this.initScene();
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

    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.08;
    this.controls.minDistance = 1.3;
    this.controls.maxDistance = 8;
    this.controls.rotateSpeed = 0.5;

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
      this.terrainData,
      { terrainColors: TERRAIN_COLORS, resourceAccents: RESOURCE_ACCENTS }
    );
  },

  initTileTextures() {
    this.tileTextures = new TileTextureGenerator(
      this.subdivisions,
      this.terrainData
    );
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
    const N = this.subdivisions;
    const [dr, dc] = DIR_OFFSETS[orientation];
    const neighborCenter = this.getTileCenter(face,
      (row + dr + N) % N,
      (col + dc + N) % N
    );

    // Project neighbor direction onto tangent plane at this tile
    const toNeighbor = new THREE.Vector3().subVectors(neighborCenter, normal);
    const tangentX = toNeighbor.addScaledVector(normal, -toNeighbor.dot(normal)).normalize();
    const tangentZ = new THREE.Vector3().crossVectors(tangentX, normal).normalize();

    const m = new THREE.Matrix4().makeBasis(tangentX, normal, tangentZ);
    mesh.quaternion.setFromRotationMatrix(m);

    this.scene.add(mesh);
    this.buildingMeshes[key] = mesh;

    // Regenerate tile texture for this face
    this.regenerateFaceTexture(face);
  },

  removeBuildingFromScene(face, row, col) {
    const key = `${face}:${row}:${col}`;
    const mesh = this.buildingMeshes[key];
    if (mesh) {
      this.scene.remove(mesh);
      delete this.buildingMeshes[key];
    }
    this.buildingData.delete(key);

    // Regenerate tile texture for this face
    this.regenerateFaceTexture(face);
  },

  /**
   * Regenerate the Canvas2D texture for a face and apply it to the face mesh.
   */
  regenerateFaceTexture(faceId) {
    const N = this.chunkManager.getFaceLOD(faceId);
    if (N === 0) return;

    const texture = this.tileTextures.generateTexture(faceId, N, this.buildingData);
    const faceMesh = this.chunkManager.faceMeshes[faceId];
    if (faceMesh) {
      faceMesh.material.map = texture;
      faceMesh.material.needsUpdate = true;
    }
  },

  // --- LiveView event handlers ---

  setupEventHandlers() {
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
      this.placementType = type;
      this.placementOrientation = orientation ?? 0;
      this.clearPreviewArrow();
      // Re-show preview if currently hovering a tile
      if (this.placementType && this.hoveredTile) {
        this.showPreviewArrow(this.hoveredTile.face, this.hoveredTile.row, this.hoveredTile.col);
      }
    });

    this.handleEvent("restore_player", ({ player_id, player_name, player_color, camera }) => {
      // Persist identity to localStorage so it survives reconnects
      try {
        localStorage.setItem("spheric_player_id", player_id);
        localStorage.setItem("spheric_player_name", player_name);
        localStorage.setItem("spheric_player_color", player_color);
      } catch (_e) { /* localStorage unavailable */ }

      // Restore camera position and orbit target
      if (camera && camera.z != null) {
        this.camera.position.set(camera.x, camera.y, camera.z);
        if (camera.tx != null) {
          this.controls.target.set(camera.tx, camera.ty, camera.tz);
        }
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
    const tile = this.hitToTile(event);
    if (!tile) return;

    // Clear previous selection
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
    const tile = this.hitToTile(event);
    if (!tile) return;

    this.pushEvent("remove_building", {
      face: tile.face,
      row: tile.row,
      col: tile.col,
    });
  },

  onTileHover(event) {
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
    const to = this.getTileCenter(face, (row + dr + N) % N, (col + dc + N) % N);
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
      new THREE.ConeGeometry(0.008, 0.02, 6),
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
          const target = this.controls.target;
          localStorage.setItem("spheric_camera_tx", target.x);
          localStorage.setItem("spheric_camera_ty", target.y);
          localStorage.setItem("spheric_camera_tz", target.z);
        } catch (_e) { /* localStorage unavailable */ }
      }
    }, 500);
  },

  // --- Render loop ---

  animate() {
    this._animId = requestAnimationFrame(() => this.animate());
    this.controls.update();

    // Update LOD based on camera position (ChunkManager handles dirty checks)
    const lodChanged = this.chunkManager.update(this.camera.position);
    if (lodChanged) {
      // Regenerate textures for faces that changed LOD
      for (let faceId = 0; faceId < 30; faceId++) {
        const N = this.chunkManager.getFaceLOD(faceId);
        if (N > 0) {
          this.regenerateFaceTexture(faceId);
        }
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
  },

  destroyed() {
    if (this._animId) cancelAnimationFrame(this._animId);
    if (this._cameraTrackTimer) clearInterval(this._cameraTrackTimer);
    window.removeEventListener("resize", this._onResize);
    this.renderer.domElement.removeEventListener("click", this._onClick);
    this.renderer.domElement.removeEventListener("mousemove", this._onMouseMove);
    this.renderer.domElement.removeEventListener("contextmenu", this._onContextMenu);
    this.clearPreviewArrow();
    this.disposePlayerMarkers();
    if (this.itemRenderer) this.itemRenderer.dispose();
    if (this.chunkManager) this.chunkManager.dispose();
    if (this.tileTextures) this.tileTextures.dispose();
    this.controls.dispose();
    this.renderer.dispose();
  },
};

export default GameRenderer;
