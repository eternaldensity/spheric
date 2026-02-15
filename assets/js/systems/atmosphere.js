import * as THREE from "three";

const MOTE_COUNT = 200;

/**
 * AtmosphereRenderer manages floating dust motes near the sphere surface.
 */
export class AtmosphereRenderer {
  constructor(scene) {
    this.scene = scene;
    this._dustMotes = null;
    this._moteVelocities = null;
    this._temp = new THREE.Vector3();
    this._init();
  }

  _init() {
    const positions = new Float32Array(MOTE_COUNT * 3);
    this._moteVelocities = new Float32Array(MOTE_COUNT * 3);

    for (let i = 0; i < MOTE_COUNT; i++) {
      const theta = Math.random() * Math.PI * 2;
      const phi = Math.acos(2 * Math.random() - 1);
      const r = 1.03 + Math.random() * 0.03;
      positions[i * 3] = r * Math.sin(phi) * Math.cos(theta);
      positions[i * 3 + 1] = r * Math.sin(phi) * Math.sin(theta);
      positions[i * 3 + 2] = r * Math.cos(phi);

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
  }

  update() {
    if (!this._dustMotes) return;
    const posAttr = this._dustMotes.geometry.getAttribute("position");
    const pos = posAttr.array;
    const vel = this._moteVelocities;
    const v = this._temp;

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
  }

  dispose() {
    if (this._dustMotes) {
      this.scene.remove(this._dustMotes);
      this._dustMotes.geometry.dispose();
      this._dustMotes.material.dispose();
      this._dustMotes = null;
    }
  }
}
