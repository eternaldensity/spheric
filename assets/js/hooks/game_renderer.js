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

    this.initScene();
    this.buildSphereMesh();
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
    const N = this.subdivisions;

    for (let faceId = 0; faceId < this.faceIndices.length; faceId++) {
      const [ai, bi, ci, di] = this.faceIndices[faceId];
      const A = this.baseVertices[ai];
      const B = this.baseVertices[bi];
      const C = this.baseVertices[ci]; // unused for parallelogram, but opposite of A
      const D = this.baseVertices[di];

      // Edge vectors for parallelogram parameterization
      // Face vertices are cyclic: A, B, C, D
      // e1 = B - A, e2 = D - A
      // P(u,v) = A + (u/N)*e1 + (v/N)*e2
      const e1 = new THREE.Vector3().subVectors(B, A);
      const e2 = new THREE.Vector3().subVectors(D, A);

      // Generate (N+1)^2 vertices
      const positions = [];
      const uvs = [];
      for (let v = 0; v <= N; v++) {
        for (let u = 0; u <= N; u++) {
          const point = new THREE.Vector3()
            .copy(A)
            .addScaledVector(e1, u / N)
            .addScaledVector(e2, v / N);

          // Project to unit sphere
          point.normalize();

          positions.push(point.x, point.y, point.z);
          uvs.push(u / N, v / N);
        }
      }

      // Generate triangle indices: 2 triangles per grid cell
      const indices = [];
      for (let v = 0; v < N; v++) {
        for (let u = 0; u < N; u++) {
          const tl = v * (N + 1) + u;
          const tr = v * (N + 1) + (u + 1);
          const bl = (v + 1) * (N + 1) + u;
          const br = (v + 1) * (N + 1) + (u + 1);

          // Two triangles per cell
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
      geometry.setIndex(indices);
      geometry.computeVertexNormals();

      const material = new THREE.MeshLambertMaterial({
        color: FACE_COLORS[faceId],
      });

      const mesh = new THREE.Mesh(geometry, material);
      this.scene.add(mesh);
      this.chunkMeshes.push(mesh);

      // Grid line overlay — draw lines along u and v grid boundaries
      const gridLines = this.buildGridLines(A, e1, e2, N);
      this.scene.add(gridLines);
    }
  },

  buildGridLines(origin, e1, e2, N) {
    const linePositions = [];
    const LIFT = 1.001; // slightly above surface to prevent z-fighting

    // Lines along u direction (v = const)
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

    // Lines along v direction (u = const)
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
    window.removeEventListener("resize", this._onResize);
    this.controls.dispose();
    this.renderer.dispose();
  },
};

export default GameRenderer;
