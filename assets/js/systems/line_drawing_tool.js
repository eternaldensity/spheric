import * as THREE from "three";

// Direction offsets: orientation -> [dRow, dCol]
const DIR_OFFSETS = [
  [0, 1],   // W
  [1, 0],   // S
  [0, -1],  // E
  [-1, 0],  // N
];

/**
 * LineDrawingTool manages line-mode preview arrows and overlays.
 */
export class LineDrawingTool {
  constructor(scene, getTileCenter, chunkManager, subdivisions) {
    this.scene = scene;
    this.getTileCenter = getTileCenter;
    this.chunkManager = chunkManager;
    this.subdivisions = subdivisions;
    this.previewTiles = [];
    this.previewMeshes = [];
  }

  showPreview(path) {
    this.clearPreview();
    this.previewTiles = path;

    for (const tile of path) {
      this.chunkManager.setTileOverlay(tile.face, tile.row, tile.col, "hover");
      this._showArrowAt(tile.face, tile.row, tile.col, tile.orientation);
    }
  }

  _showArrowAt(face, row, col, orientation) {
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
    this.previewMeshes.push(group);
  }

  clearPreview() {
    for (const group of this.previewMeshes) {
      this.scene.remove(group);
      group.traverse((child) => {
        if (child.isLine || child.isMesh) {
          if (child.geometry) child.geometry.dispose();
          if (child.material) child.material.dispose();
        }
      });
    }
    this.previewMeshes = [];

    for (const tile of this.previewTiles) {
      const overlay = this.chunkManager.getTileOverlay(tile.face, tile.row, tile.col);
      if (overlay === "hover") {
        this.chunkManager.setTileOverlay(tile.face, tile.row, tile.col, null);
      }
    }
    this.previewTiles = [];
  }

  /** Cancel line draw: clear preview and start marker overlay. */
  cancel(lineStart) {
    this.clearPreview();
    if (lineStart) {
      const overlay = this.chunkManager.getTileOverlay(lineStart.face, lineStart.row, lineStart.col);
      if (overlay === "selected") {
        this.chunkManager.setTileOverlay(lineStart.face, lineStart.row, lineStart.col, null);
      }
    }
  }

  dispose() {
    this.clearPreview();
  }
}
