import * as THREE from "three";

/**
 * DroneCamera simulates a camera drone flying above the sphere surface.
 *
 * - Click on the sphere sets a destination; the drone smoothly flies there.
 * - Scroll wheel raises/lowers the hover height.
 * - Camera always looks down at the surface point directly below it.
 * - Right-click drag rotates the view around the current hover point.
 */
export class DroneCamera {
  constructor(camera, renderer, chunkManager) {
    this.camera = camera;
    this.renderer = renderer;
    this.canvas = renderer.domElement;
    this.chunkManager = chunkManager;

    // Hover height above sphere surface (sphere radius ~1.0)
    this.minHeight = 0.15;
    this.maxHeight = 7.0;
    this.height = 2.5;
    this.targetHeight = 2.5;

    // Current surface-normal position (the point on the sphere we're above)
    this._surfacePoint = new THREE.Vector3(0, 0, 1).normalize();
    this._targetSurfacePoint = new THREE.Vector3(0, 0, 1).normalize();

    // Orbit angle around the surface normal (right-drag rotation)
    this._orbitAngle = 0;
    this._targetOrbitAngle = 0;
    this._orbitTilt = 0.3; // slight tilt so we look slightly forward, not straight down
    this._targetOrbitTilt = 0.3;
    this._minTilt = 0.0;  // straight down
    this._maxTilt = 1.2;  // nearly horizontal

    // Interpolation speed (0-1 range, higher = snappier)
    this._flySpeed = 3.0;    // surface point interpolation
    this._heightSpeed = 5.0;  // height interpolation
    this._orbitSpeed = 8.0;   // orbit angle interpolation

    // Flying state
    this._isFlying = false;
    this._suppressClick = false;

    // Right-drag orbit state
    this._isDragging = false;
    this._dragStartX = 0;
    this._dragStartY = 0;
    this._dragStartOrbit = 0;
    this._dragStartTilt = 0;
    this._dragMoved = false;

    // Reusable objects
    this._raycaster = new THREE.Raycaster();
    this._mouse = new THREE.Vector2();
    this._tempVec = new THREE.Vector3();
    this._tempQuat = new THREE.Quaternion();

    // Bind event handlers
    this._onWheel = (e) => this._handleWheel(e);
    this._onPointerDown = (e) => this._handlePointerDown(e);
    this._onPointerMove = (e) => this._handlePointerMove(e);
    this._onPointerUp = (e) => this._handlePointerUp(e);
    this._onContextMenu = (e) => e.preventDefault();

    this.canvas.addEventListener("wheel", this._onWheel, { passive: false });
    this.canvas.addEventListener("pointerdown", this._onPointerDown);
    this.canvas.addEventListener("contextmenu", this._onContextMenu);

    // Apply initial camera position
    this._applyCameraPosition();
  }

  /** Whether the drone is currently flying to a destination. */
  get isFlying() { return this._isFlying; }

  /** Whether a click should be suppressed (after a drag). */
  get suppressClick() { return this._suppressClick; }

  /** Whether the user is currently dragging to orbit. */
  get isDragging() { return this._isDragging; }

  /** The current surface point the drone hovers above. */
  get surfacePoint() { return this._surfacePoint.clone(); }

  /**
   * Set a destination for the drone to fly to.
   * @param {THREE.Vector3} point - Point on sphere surface (will be normalized)
   */
  flyTo(point) {
    this._targetSurfacePoint.copy(point).normalize();
    this._isFlying = true;
  }

  /**
   * Immediately set position (no animation), e.g. for restoring saved state.
   */
  setPosition(surfacePoint, height, orbitAngle, orbitTilt) {
    this._surfacePoint.copy(surfacePoint).normalize();
    this._targetSurfacePoint.copy(this._surfacePoint);
    if (height != null) {
      this.height = Math.max(this.minHeight, Math.min(this.maxHeight, height));
      this.targetHeight = this.height;
    }
    if (orbitAngle != null) {
      this._orbitAngle = orbitAngle;
      this._targetOrbitAngle = orbitAngle;
    }
    if (orbitTilt != null) {
      this._orbitTilt = orbitTilt;
      this._targetOrbitTilt = orbitTilt;
    }
    this._applyCameraPosition();
  }

  /**
   * Restore camera from a saved position vector (old format compatibility).
   * Extracts surface point and height from camera world position.
   */
  restoreFromCameraPos(x, y, z) {
    const pos = new THREE.Vector3(x, y, z);
    const dist = pos.length();
    if (dist < 0.01) return;
    this._surfacePoint.copy(pos).normalize();
    this._targetSurfacePoint.copy(this._surfacePoint);
    this.height = Math.max(this.minHeight, Math.min(this.maxHeight, dist - 1.0));
    this.targetHeight = this.height;
    this._applyCameraPosition();
  }

  /**
   * Update each frame. Call with delta time in seconds.
   */
  update(dt) {
    const t = Math.min(1.0, dt);

    // Interpolate height
    const heightDiff = this.targetHeight - this.height;
    if (Math.abs(heightDiff) > 0.0001) {
      this.height += heightDiff * Math.min(1.0, this._heightSpeed * t);
    } else {
      this.height = this.targetHeight;
    }

    // Interpolate orbit angle
    let orbitDiff = this._targetOrbitAngle - this._orbitAngle;
    if (Math.abs(orbitDiff) > 0.0001) {
      this._orbitAngle += orbitDiff * Math.min(1.0, this._orbitSpeed * t);
    } else {
      this._orbitAngle = this._targetOrbitAngle;
    }

    // Interpolate orbit tilt
    let tiltDiff = this._targetOrbitTilt - this._orbitTilt;
    if (Math.abs(tiltDiff) > 0.0001) {
      this._orbitTilt += tiltDiff * Math.min(1.0, this._orbitSpeed * t);
    } else {
      this._orbitTilt = this._targetOrbitTilt;
    }

    // Interpolate surface point via spherical lerp
    const angle = this._surfacePoint.angleTo(this._targetSurfacePoint);
    if (angle > 0.001) {
      const lerpFactor = Math.min(1.0, this._flySpeed * t);
      // Use quaternion-based slerp for great-circle path
      this._tempQuat.setFromUnitVectors(this._surfacePoint, this._targetSurfacePoint);
      // Partial rotation
      this._tempQuat.slerp(new THREE.Quaternion(), 1.0 - lerpFactor);
      // Apply the inverse of the partial remaining to get partial progress
      const fullQuat = new THREE.Quaternion().setFromUnitVectors(this._surfacePoint, this._targetSurfacePoint);
      const partialQuat = new THREE.Quaternion().slerpQuaternions(
        new THREE.Quaternion(), fullQuat, lerpFactor
      );
      this._surfacePoint.applyQuaternion(partialQuat).normalize();
    } else {
      this._surfacePoint.copy(this._targetSurfacePoint);
      this._isFlying = false;
    }

    this._applyCameraPosition();
  }

  /**
   * Apply the current state to the actual camera transform.
   */
  _applyCameraPosition() {
    const normal = this._surfacePoint;

    // Build a local coordinate frame on the sphere surface
    // "up" = normal, find tangent axes
    const up = this._tempVec.set(0, 1, 0);
    if (Math.abs(normal.dot(up)) > 0.99) {
      up.set(1, 0, 0);
    }
    const tangentX = new THREE.Vector3().crossVectors(up, normal).normalize();
    const tangentY = new THREE.Vector3().crossVectors(normal, tangentX).normalize();

    // Orbit: offset the camera position around the normal axis
    // tilt=0 means directly above, tilt>0 means offset to the side (looking at an angle)
    const orbX = Math.sin(this._orbitAngle) * Math.sin(this._orbitTilt);
    const orbY = Math.cos(this._orbitAngle) * Math.sin(this._orbitTilt);
    const orbZ = Math.cos(this._orbitTilt); // vertical component

    const offset = new THREE.Vector3()
      .addScaledVector(tangentX, orbX)
      .addScaledVector(tangentY, orbY)
      .addScaledVector(normal, orbZ)
      .normalize();

    // Position camera at height above surface along the offset direction
    const camDist = 1.0 + this.height;
    this.camera.position.copy(offset).multiplyScalar(camDist);

    // Look at the surface point
    this.camera.lookAt(normal.clone().multiplyScalar(1.0));

    // Fix the camera "up" to align with the surface normal for stable orientation
    this.camera.up.copy(normal);
  }

  /**
   * Raycast from screen coords to find a point on the sphere.
   * Returns the hit point (THREE.Vector3) or null.
   */
  raycastSphere(clientX, clientY) {
    this._mouse.x = (clientX / window.innerWidth) * 2 - 1;
    this._mouse.y = -(clientY / window.innerHeight) * 2 + 1;

    this._raycaster.setFromCamera(this._mouse, this.camera);
    const meshes = this.chunkManager.getRaycastMeshes();
    const intersects = this._raycaster.intersectObjects(meshes);

    if (intersects.length === 0) return null;
    return intersects[0].point.clone();
  }

  _handleWheel(event) {
    event.preventDefault();
    const delta = event.deltaY > 0 ? 1 : -1;
    // Scale scroll step with current height for consistent feel
    const step = 0.05 + this.targetHeight * 0.08;
    this.targetHeight = Math.max(
      this.minHeight,
      Math.min(this.maxHeight, this.targetHeight + delta * step)
    );
  }

  _handlePointerDown(event) {
    // Right-click or middle-click: start orbit drag
    if (event.button === 2 || event.button === 1) {
      this._isDragging = true;
      this._dragStartX = event.clientX;
      this._dragStartY = event.clientY;
      this._dragStartOrbit = this._targetOrbitAngle;
      this._dragStartTilt = this._targetOrbitTilt;
      this._dragMoved = false;

      this.canvas.setPointerCapture(event.pointerId);
      this._dragPointerId = event.pointerId;

      document.addEventListener("pointermove", this._onPointerMove);
      document.addEventListener("pointerup", this._onPointerUp);

      event.preventDefault();
    }
  }

  _handlePointerMove(event) {
    if (!this._isDragging) return;

    const dx = event.clientX - this._dragStartX;
    const dy = event.clientY - this._dragStartY;

    if (Math.abs(dx) > 3 || Math.abs(dy) > 3) {
      this._dragMoved = true;
    }

    const sensitivity = 0.005;
    this._targetOrbitAngle = this._dragStartOrbit + dx * sensitivity;
    this._targetOrbitTilt = Math.max(
      this._minTilt,
      Math.min(this._maxTilt, this._dragStartTilt + dy * sensitivity)
    );
  }

  _handlePointerUp(event) {
    if (!this._isDragging) return;
    this._isDragging = false;

    try {
      this.canvas.releasePointerCapture(this._dragPointerId);
    } catch (_e) { /* already released */ }

    document.removeEventListener("pointermove", this._onPointerMove);
    document.removeEventListener("pointerup", this._onPointerUp);

    if (this._dragMoved) {
      this._suppressClick = true;
      requestAnimationFrame(() => { this._suppressClick = false; });
    }
  }

  /**
   * Get camera state for persistence.
   */
  getState() {
    return {
      sx: this._surfacePoint.x,
      sy: this._surfacePoint.y,
      sz: this._surfacePoint.z,
      height: this.height,
      orbit: this._orbitAngle,
      tilt: this._orbitTilt,
    };
  }

  /**
   * Restore full drone state from persisted data.
   */
  restoreState(state) {
    if (state.sx != null) {
      this._surfacePoint.set(state.sx, state.sy, state.sz).normalize();
      this._targetSurfacePoint.copy(this._surfacePoint);
    }
    if (state.height != null) {
      this.height = Math.max(this.minHeight, Math.min(this.maxHeight, state.height));
      this.targetHeight = this.height;
    }
    if (state.orbit != null) {
      this._orbitAngle = state.orbit;
      this._targetOrbitAngle = state.orbit;
    }
    if (state.tilt != null) {
      this._orbitTilt = state.tilt;
      this._targetOrbitTilt = state.tilt;
    }
    this._applyCameraPosition();
  }

  dispose() {
    this.canvas.removeEventListener("wheel", this._onWheel);
    this.canvas.removeEventListener("pointerdown", this._onPointerDown);
    this.canvas.removeEventListener("contextmenu", this._onContextMenu);
    document.removeEventListener("pointermove", this._onPointerMove);
    document.removeEventListener("pointerup", this._onPointerUp);
  }
}
