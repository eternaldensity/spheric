import * as THREE from "three";
import { OrbitControls } from "three/examples/jsm/controls/OrbitControls.js";

// Color palette for face chunks — gives each face a slightly different hue
// so you can see the 30 individual faces on the sphere
const FACE_COLORS = (() => {
  const colors = [];
  for (let i = 0; i < 30; i++) {
    const hue = (i * 137.508) % 360; // golden angle spacing
    colors.push(new THREE.Color().setHSL(hue / 360, 0.35, 0.55));
  }
  return colors;
})();

const HIGHLIGHT_COLOR = new THREE.Color(0xffdd44);
const HOVER_COLOR = new THREE.Color(0xaaddff);

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

    this.initScene();
    this.buildSphereMesh();
    this.setupRaycasting();
    this.setupCameraTracking();
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
    // Store per-face color arrays so we can highlight individual tiles
    this.faceColorArrays = [];
    // Store per-face base colors for reset
    this.faceBaseColors = [];
    const N = this.subdivisions;

    for (let faceId = 0; faceId < this.faceIndices.length; faceId++) {
      const [ai, bi, ci, di] = this.faceIndices[faceId];
      const A = this.baseVertices[ai];
      const B = this.baseVertices[bi];
      const C = this.baseVertices[ci];
      const D = this.baseVertices[di];

      const e1 = new THREE.Vector3().subVectors(B, A);
      const e2 = new THREE.Vector3().subVectors(D, A);

      // Generate (N+1)^2 vertices
      const positions = [];
      const uvs = [];
      const colors = [];
      const baseColor = FACE_COLORS[faceId];

      for (let v = 0; v <= N; v++) {
        for (let u = 0; u <= N; u++) {
          const point = new THREE.Vector3()
            .copy(A)
            .addScaledVector(e1, u / N)
            .addScaledVector(e2, v / N);
          point.normalize();

          positions.push(point.x, point.y, point.z);
          uvs.push(u / N, v / N);
          colors.push(baseColor.r, baseColor.g, baseColor.b);
        }
      }

      // Generate triangle indices
      const indices = [];
      for (let v = 0; v < N; v++) {
        for (let u = 0; u < N; u++) {
          const tl = v * (N + 1) + u;
          const tr = v * (N + 1) + (u + 1);
          const bl = (v + 1) * (N + 1) + u;
          const br = (v + 1) * (N + 1) + (u + 1);
          indices.push(tl, bl, tr);
          indices.push(tr, bl, br);
        }
      }

      const geometry = new THREE.BufferGeometry();
      geometry.setAttribute(
        "position",
        new THREE.Float32BufferAttribute(positions, 3)
      );
      geometry.setAttribute("uv", new THREE.Float32BufferAttribute(uvs, 2));

      const colorAttr = new THREE.Float32BufferAttribute(colors, 3);
      geometry.setAttribute("color", colorAttr);
      geometry.setIndex(indices);
      geometry.computeVertexNormals();

      const material = new THREE.MeshLambertMaterial({
        vertexColors: true,
      });

      const mesh = new THREE.Mesh(geometry, material);
      this.scene.add(mesh);
      this.chunkMeshes.push(mesh);
      this.faceColorArrays.push(colorAttr);
      this.faceBaseColors.push(baseColor.clone());

      // Grid line overlay
      const gridLines = this.buildGridLines(A, e1, e2, N);
      this.scene.add(gridLines);
    }
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
    lineGeo.setAttribute(
      "position",
      new THREE.Float32BufferAttribute(linePositions, 3)
    );
    const lineMat = new THREE.LineBasicMaterial({
      color: 0x000000,
      opacity: 0.15,
      transparent: true,
    });
    return new THREE.LineSegments(lineGeo, lineMat);
  },

  // --- Raycasting for tile selection ---

  setupRaycasting() {
    this.raycaster = new THREE.Raycaster();
    this.mouse = new THREE.Vector2();

    this._onClick = (event) => this.onTileClick(event);
    this._onMouseMove = (event) => this.onTileHover(event);
    this.renderer.domElement.addEventListener("click", this._onClick);
    this.renderer.domElement.addEventListener("mousemove", this._onMouseMove);
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

    // Each grid cell has 2 triangles. faceIndex is the triangle index
    // within this mesh. Cell index = floor(faceIndex / 2).
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
      this.setTileColor(
        this.selectedTile.face,
        this.selectedTile.row,
        this.selectedTile.col,
        this.faceBaseColors[this.selectedTile.face]
      );
    }

    this.selectedTile = tile;
    this.setTileColor(tile.face, tile.row, tile.col, HIGHLIGHT_COLOR);

    // Send to server
    this.pushEvent("tile_click", {
      face: tile.face,
      row: tile.row,
      col: tile.col,
    });
  },

  onTileHover(event) {
    const tile = this.hitToTile(event);

    // Clear previous hover (unless it's the selected tile)
    if (this.hoveredTile) {
      const h = this.hoveredTile;
      const isSelected =
        this.selectedTile &&
        this.selectedTile.face === h.face &&
        this.selectedTile.row === h.row &&
        this.selectedTile.col === h.col;
      if (!isSelected) {
        this.setTileColor(h.face, h.row, h.col, this.faceBaseColors[h.face]);
      }
    }

    this.hoveredTile = tile;

    if (tile) {
      const isSelected =
        this.selectedTile &&
        this.selectedTile.face === tile.face &&
        this.selectedTile.row === tile.row &&
        this.selectedTile.col === tile.col;
      if (!isSelected) {
        this.setTileColor(tile.face, tile.row, tile.col, HOVER_COLOR);
      }
    }
  },

  setTileColor(faceId, row, col, color) {
    const N = this.subdivisions;
    const colorAttr = this.faceColorArrays[faceId];
    const arr = colorAttr.array;

    // The 4 corner vertices of grid cell (row, col) are:
    //   tl = row*(N+1) + col
    //   tr = row*(N+1) + (col+1)
    //   bl = (row+1)*(N+1) + col
    //   br = (row+1)*(N+1) + (col+1)
    const corners = [
      row * (N + 1) + col,
      row * (N + 1) + (col + 1),
      (row + 1) * (N + 1) + col,
      (row + 1) * (N + 1) + (col + 1),
    ];

    for (const vi of corners) {
      arr[vi * 3] = color.r;
      arr[vi * 3 + 1] = color.g;
      arr[vi * 3 + 2] = color.b;
    }

    colorAttr.needsUpdate = true;
  },

  // --- Camera tracking ---

  setupCameraTracking() {
    this._lastCameraPos = new THREE.Vector3();
    this._cameraTrackTimer = null;

    // Send camera position every 500ms, but only if it actually moved
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
    this.controls.dispose();
    this.renderer.dispose();
  },
};

export default GameRenderer;
