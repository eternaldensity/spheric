import * as THREE from "three";

/**
 * SpinControl handles Ctrl+drag rotation of the camera around a point on the sphere.
 */
export class SpinControl {
  constructor(canvas, camera, controls, chunkManager) {
    this.canvas = canvas;
    this.camera = camera;
    this.controls = controls;
    this.chunkManager = chunkManager;

    this._spinning = false;
    this._spinAxis = new THREE.Vector3();
    this._spinLastX = 0;
    this._spinVelocity = 0;
    this._suppressClick = false;
    this._spinQuat = new THREE.Quaternion();
    this._spinPointerId = null;

    // Reusable raycaster/mouse for spin hit-test
    this._raycaster = new THREE.Raycaster();
    this._mouse = new THREE.Vector2();

    this._onPointerDown = (event) => this._handlePointerDown(event);
    this._onPointerMove = (event) => this._handlePointerMove(event);
    this._onPointerUp = (event) => this._handlePointerUp(event);

    // Capture phase fires before TrackballControls' bubble-phase listener
    this.canvas.addEventListener("pointerdown", this._onPointerDown, true);
  }

  get spinning() { return this._spinning; }
  get suppressClick() { return this._suppressClick; }
  get velocity() { return this._spinVelocity; }

  _handlePointerDown(event) {
    if (event.button !== 0 || !event.ctrlKey) return;

    this._mouse.x = (event.clientX / window.innerWidth) * 2 - 1;
    this._mouse.y = -(event.clientY / window.innerHeight) * 2 + 1;
    this._raycaster.setFromCamera(this._mouse, this.camera);
    const meshes = this.chunkManager.getRaycastMeshes();
    const intersects = this._raycaster.intersectObjects(meshes);

    if (intersects.length === 0) return;

    this._spinAxis.copy(intersects[0].point).normalize();
    this._spinning = true;
    this._spinLastX = event.clientX;
    this._spinVelocity = 0;

    event.stopPropagation();
    event.preventDefault();

    this.controls.enabled = false;
    this.controls._lastAngle = 0;

    this.canvas.setPointerCapture(event.pointerId);
    this._spinPointerId = event.pointerId;
    document.addEventListener("pointermove", this._onPointerMove);
    document.addEventListener("pointerup", this._onPointerUp);
  }

  _handlePointerMove(event) {
    if (!this._spinning) return;

    const deltaX = event.clientX - this._spinLastX;
    this._spinLastX = event.clientX;

    const sensitivity = 0.005;
    const angle = deltaX * sensitivity;

    if (Math.abs(angle) > 0.0001) {
      this._applyRotation(angle);
      this._spinVelocity = angle;
    }
  }

  _handlePointerUp() {
    if (!this._spinning) return;
    this._spinning = false;

    try {
      this.canvas.releasePointerCapture(this._spinPointerId);
    } catch (_e) { /* already released */ }

    document.removeEventListener("pointermove", this._onPointerMove);
    document.removeEventListener("pointerup", this._onPointerUp);

    this.controls.enabled = true;
    this.controls._lastPosition.copy(this.camera.position);

    this._suppressClick = true;
    requestAnimationFrame(() => { this._suppressClick = false; });
  }

  _applyRotation(angle) {
    this._spinQuat.setFromAxisAngle(this._spinAxis, angle);
    this.camera.position.applyQuaternion(this._spinQuat);
    this.camera.up.applyQuaternion(this._spinQuat);
    this.camera.lookAt(this.controls.target);
  }

  /** Called each frame to apply velocity damping after release. */
  updateDamping() {
    if (!this._spinning && Math.abs(this._spinVelocity) > 0.0001) {
      this._applyRotation(this._spinVelocity);
      this._spinVelocity *= (1.0 - this.controls.dynamicDampingFactor);
      if (Math.abs(this._spinVelocity) < 0.00005) {
        this._spinVelocity = 0;
      }
    }
  }

  dispose() {
    this.canvas.removeEventListener("pointerdown", this._onPointerDown, true);
    document.removeEventListener("pointermove", this._onPointerMove);
    document.removeEventListener("pointerup", this._onPointerUp);
  }
}
