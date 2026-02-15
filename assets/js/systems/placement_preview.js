import * as THREE from "three";

// Direction offsets: orientation -> [dRow, dCol]
const DIR_OFFSETS = [
  [0, 1],   // W
  [1, 0],   // S
  [0, -1],  // E
  [-1, 0],  // N
];

/**
 * PlacementPreview shows a directional arrow on hover during building placement.
 */
export class PlacementPreview {
  constructor(scene, getTileCenter, subdivisions) {
    this.scene = scene;
    this.getTileCenter = getTileCenter;
    this.subdivisions = subdivisions;
    this._arrow = null;
  }

  show(face, row, col, orientation) {
    this.clear();

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
    const shaftMat = new THREE.LineBasicMaterial({ color: 0xffdd44, linewidth: 2 });
    const shaft = new THREE.Line(shaftGeo, shaftMat);

    const cone = new THREE.Mesh(
      new THREE.ConeGeometry(0.002, 0.005, 6),
      new THREE.MeshBasicMaterial({ color: 0xffdd44 })
    );
    cone.position.copy(end);
    cone.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir);

    const group = new THREE.Group();
    group.add(shaft);
    group.add(cone);
    this.scene.add(group);
    this._arrow = group;
  }

  clear() {
    if (this._arrow) {
      this.scene.remove(this._arrow);
      this._disposeGroup(this._arrow);
      this._arrow = null;
    }
  }

  _disposeGroup(group) {
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
  }

  dispose() {
    this.clear();
  }
}
