import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";
import { createBuildingMesh } from "../buildings/building_factory.js";
import { ItemInterpolator } from "../systems/item_interpolator.js";
import { ItemRenderer } from "../systems/item_renderer.js";

// Terrain biome colors
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

// Overlay tints — blended on top of base terrain color
const HIGHLIGHT_TINT = new THREE.Color(0xffdd44);
const HOVER_TINT = new THREE.Color(0xaaddff);
const ERROR_TINT = new THREE.Color(0xff2222);

const HIGHLIGHT_BLEND = 0.55;
const HOVER_BLEND = 0.35;

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
    this.selectedBuildingType = null;

    // Per-face tile overlay state: faceOverlays[faceId] = Map of (row*N+col) -> "selected"|"hover"|null
    this.faceOverlays = [];

    // Store per-face edge vectors for tile center computation
    this.faceEdges = [];

    this.initScene();
    this.buildSphereMesh();
    this.setupRaycasting();
    this.setupCameraTracking();
    this.setupEventHandlers();

    // Item interpolation and rendering
    this.itemInterpolator = new ItemInterpolator();
    this.itemRenderer = new ItemRenderer(
      this.scene,
      (face, row, col) => this.getTileCenter(face, row, col)
    );

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

  buildSphereMesh() {
    this.chunkMeshes = [];
    this.faceColorArrays = [];
    this.faceBaseColors = []; // per-tile base colors: faceBaseColors[faceId][tileIndex] = Color
    const N = this.subdivisions;

    for (let faceId = 0; faceId < this.faceIndices.length; faceId++) {
      const [ai, bi, ci, di] = this.faceIndices[faceId];
      const A = this.baseVertices[ai];
      const B = this.baseVertices[bi];
      const C = this.baseVertices[ci];
      const D = this.baseVertices[di];

      const e1 = new THREE.Vector3().subVectors(B, A);
      const e2 = new THREE.Vector3().subVectors(D, A);

      // Store for tile center computation
      this.faceEdges.push({ origin: A.clone(), e1: e1.clone(), e2: e2.clone() });

      // Compute per-tile terrain colors
      const tileColors = [];
      const faceTerrain = this.terrainData[faceId];
      for (let row = 0; row < N; row++) {
        for (let col = 0; col < N; col++) {
          const td = faceTerrain[row][col];
          const baseColor = (TERRAIN_COLORS[td.t] || TERRAIN_COLORS.grassland).clone();
          if (td.r && RESOURCE_ACCENTS[td.r]) {
            baseColor.lerp(RESOURCE_ACCENTS[td.r], 0.55);
          }
          tileColors.push(baseColor);
        }
      }

      // Generate (N+1)^2 vertices
      const positions = [];
      const uvs = [];
      const colors = [];

      for (let v = 0; v <= N; v++) {
        for (let u = 0; u <= N; u++) {
          const point = new THREE.Vector3()
            .copy(A)
            .addScaledVector(e1, u / N)
            .addScaledVector(e2, v / N);
          point.normalize();

          positions.push(point.x, point.y, point.z);
          uvs.push(u / N, v / N);

          // Vertex color: average of adjacent tile colors
          const color = this.vertexTerrainColor(v, u, N, tileColors);
          colors.push(color.r, color.g, color.b);
        }
      }

      // Generate triangle indices with correct winding
      const indices = [];
      const p0 = new THREE.Vector3(positions[0], positions[1], positions[2]);
      const p1idx = (N + 1) * 3;
      const p1 = new THREE.Vector3(positions[p1idx], positions[p1idx + 1], positions[p1idx + 2]);
      const p2 = new THREE.Vector3(positions[3], positions[4], positions[5]);
      const edge1 = new THREE.Vector3().subVectors(p1, p0);
      const edge2 = new THREE.Vector3().subVectors(p2, p0);
      const testNormal = new THREE.Vector3().crossVectors(edge1, edge2);
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
      this.chunkMeshes.push(mesh);
      this.faceColorArrays.push(colorAttr);
      this.faceBaseColors.push(tileColors);
      this.faceOverlays.push(new Map());

      // Grid line overlay
      const gridLines = this.buildGridLines(A, e1, e2, N);
      this.scene.add(gridLines);
    }
  },

  // Compute vertex color by averaging adjacent tile terrain colors
  vertexTerrainColor(v, u, N, tileColors) {
    const adjacent = [];
    // A vertex at grid position (v, u) is shared by up to 4 tiles:
    // (v-1, u-1), (v-1, u), (v, u-1), (v, u)
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
  },

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
  },

  // --- Tile center computation ---

  getTileCenter(faceId, row, col) {
    const N = this.subdivisions;
    const { origin, e1, e2 } = this.faceEdges[faceId];
    const center = new THREE.Vector3()
      .copy(origin)
      .addScaledVector(e1, (col + 0.5) / N)
      .addScaledVector(e2, (row + 0.5) / N);
    center.normalize();
    return center;
  },

  // --- Building placement on sphere ---

  addBuildingToScene(face, row, col, type, orientation) {
    const key = `${face}:${row}:${col}`;

    // Remove existing mesh if any
    if (this.buildingMeshes[key]) {
      this.scene.remove(this.buildingMeshes[key]);
    }

    const mesh = createBuildingMesh(type);
    const normal = this.getTileCenter(face, row, col).normalize();

    // Position slightly above surface
    mesh.position.copy(normal).multiplyScalar(1.005);

    // Build orientation from face grid vectors so the arrow aligns with
    // the actual tile directions (orientation 0 = e1 = col+1 = "Right")
    const { e1, e2 } = this.faceEdges[face];

    // Project e1 onto the tangent plane at this tile center
    const tangentX = e1.clone().addScaledVector(normal, -e1.dot(normal)).normalize();
    const tangentZ = new THREE.Vector3().crossVectors(tangentX, normal).normalize();

    // Rotation matrix: mesh local X -> tangentX, Y -> normal, Z -> tangentZ
    const m = new THREE.Matrix4().makeBasis(tangentX, normal, tangentZ);

    // Apply orientation rotation around the normal (0=Right, 1=Down, 2=Left, 3=Up)
    if (orientation > 0) {
      const rot = new THREE.Matrix4().makeRotationAxis(normal, (orientation * Math.PI) / 2);
      m.premultiply(rot);
    }

    mesh.quaternion.setFromRotationMatrix(m);

    this.scene.add(mesh);
    this.buildingMeshes[key] = mesh;
  },

  removeBuildingFromScene(face, row, col) {
    const key = `${face}:${row}:${col}`;
    const mesh = this.buildingMeshes[key];
    if (mesh) {
      this.scene.remove(mesh);
      delete this.buildingMeshes[key];
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
    const intersects = this.raycaster.intersectObjects(this.chunkMeshes);

    if (intersects.length === 0) return null;

    const hit = intersects[0];
    const faceId = this.chunkMeshes.indexOf(hit.object);
    if (faceId === -1) return null;

    const cellIndex = Math.floor(hit.faceIndex / 2);
    const N = this.subdivisions;
    const row = Math.floor(cellIndex / N);
    const col = cellIndex % N;

    return { face: faceId, row, col };
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
      // Only clear if overlay is "hover" (don't touch "selected")
      if (overlay === "hover") {
        this.setTileOverlay(h.face, h.row, h.col, null);
      }
    }

    this.hoveredTile = tile;

    if (tile) {
      const overlay = this.getTileOverlay(tile.face, tile.row, tile.col);
      // Only apply hover if not already selected
      if (overlay !== "selected") {
        this.setTileOverlay(tile.face, tile.row, tile.col, "hover");
      }
    }
  },

  // --- Overlay-aware color system ---

  getTileOverlay(faceId, row, col) {
    const N = this.subdivisions;
    return this.faceOverlays[faceId].get(row * N + col) || null;
  },

  setTileOverlay(faceId, row, col, overlay) {
    const N = this.subdivisions;
    const key = row * N + col;

    if (overlay) {
      this.faceOverlays[faceId].set(key, overlay);
    } else {
      this.faceOverlays[faceId].delete(key);
    }

    // Recompute colors for all vertices touched by this tile
    this.refreshTileVertices(faceId, row, col);
  },

  // Recompute the 4 corner vertices of a tile, averaging across all adjacent tiles
  refreshTileVertices(faceId, row, col) {
    const N = this.subdivisions;
    const colorAttr = this.faceColorArrays[faceId];
    const arr = colorAttr.array;

    // The 4 corner vertices at grid positions (row,col), (row,col+1), (row+1,col), (row+1,col+1)
    for (let dv = 0; dv <= 1; dv++) {
      for (let du = 0; du <= 1; du++) {
        const v = row + dv;
        const u = col + du;
        const vi = v * (N + 1) + u;
        const color = this.computeVertexColor(faceId, v, u);
        arr[vi * 3] = color.r;
        arr[vi * 3 + 1] = color.g;
        arr[vi * 3 + 2] = color.b;
      }
    }

    colorAttr.needsUpdate = true;
  },

  // Compute a vertex color by averaging the effective colors of all adjacent tiles
  computeVertexColor(faceId, v, u) {
    const N = this.subdivisions;
    const tileColors = this.faceBaseColors[faceId];
    const overlays = this.faceOverlays[faceId];
    const adjacent = [];

    for (let dv = -1; dv <= 0; dv++) {
      for (let du = -1; du <= 0; du++) {
        const row = v + dv;
        const col = u + du;
        if (row >= 0 && row < N && col >= 0 && col < N) {
          const tileIdx = row * N + col;
          const base = tileColors[tileIdx];
          const overlay = overlays.get(tileIdx);
          const resourceType = this.terrainData[faceId][row][col].r;
          adjacent.push(this.applyOverlay(base, overlay, resourceType));
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
  },

  // Blend an overlay tint onto a base terrain color
  applyOverlay(baseColor, overlay, resourceType) {
    if (!overlay) return baseColor;
    const result = baseColor.clone();
    if (overlay === "selected") {
      result.lerp(HIGHLIGHT_TINT, HIGHLIGHT_BLEND);
    } else if (overlay === "hover") {
      if (resourceType && RESOURCE_ACCENTS[resourceType]) {
        // Brighten toward a vivid version of the resource color
        const vivid = RESOURCE_ACCENTS[resourceType].clone();
        vivid.offsetHSL(0, 0.3, 0.2);
        result.lerp(vivid, 0.55);
      } else {
        result.lerp(HOVER_TINT, HOVER_BLEND);
      }
    } else if (overlay === "error") {
      result.lerp(ERROR_TINT, 0.6);
    }
    return result;
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
      }
    }, 500);
  },

  // --- Render loop ---

  animate() {
    this._animId = requestAnimationFrame(() => this.animate());
    this.controls.update();

    // Update item positions with interpolation
    const now = performance.now();
    const interpolated = this.itemInterpolator.getInterpolatedItems(now);
    this.itemRenderer.update(interpolated);

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
    this.renderer.domElement.removeEventListener("click", this._onClick);
    this.renderer.domElement.removeEventListener("mousemove", this._onMouseMove);
    this.renderer.domElement.removeEventListener("contextmenu", this._onContextMenu);
    if (this.itemRenderer) this.itemRenderer.dispose();
    this.controls.dispose();
    this.renderer.dispose();
  },
};

export default GameRenderer;
