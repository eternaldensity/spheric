import * as THREE from "three";

/**
 * DroneCamera simulates a camera drone flying above the sphere surface.
 *
 * - Click on the sphere sets a destination; the drone smoothly flies there.
 * - Scroll wheel raises/lowers the hover height.
 * - Camera always sits directly above its surface point.
 * - Right-click drag tilts/rotates the viewing direction.
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

    // Persistent "north" tangent vector — parallel-transported as the drone
    // moves so the frame never snaps.  Initialised from a global reference.
    this._north = this._initNorth(this._surfacePoint);

    // Orbit angle around the surface normal (right-drag rotation)
    this._orbitAngle = 0;
    this._targetOrbitAngle = 0;
    this._orbitTilt = 0.3;
    this._targetOrbitTilt = 0.3;
    this._minTilt = 0.0;
    this._maxTilt = 1.2;

    // Interpolation speed
    this._flySpeed = 3.0;
    this._heightSpeed = 5.0;
    this._orbitSpeed = 8.0;

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

    // Bind event handlers
    this._onWheel = (e) => this._handleWheel(e);
    this._onPointerDown = (e) => this._handlePointerDown(e);
    this._onPointerMove = (e) => this._handlePointerMove(e);
    this._onPointerUp = (e) => this._handlePointerUp(e);
    this._onContextMenu = (e) => e.preventDefault();

    this.canvas.addEventListener("wheel", this._onWheel, { passive: false });
    this.canvas.addEventListener("pointerdown", this._onPointerDown);
    this.canvas.addEventListener("contextmenu", this._onContextMenu);

    this._applyCameraPosition();
  }

  get isFlying() { return this._isFlying; }
  get suppressClick() { return this._suppressClick; }
  get isDragging() { return this._isDragging; }
  get surfacePoint() { return this._surfacePoint.clone(); }

  /**
   * Compute an initial "north" tangent for a given normal.
   * Only used once at construction / restore — after that it's parallel-transported.
   */
  _initNorth(normal) {
    const ref = new THREE.Vector3(0, 1, 0);
    if (Math.abs(normal.dot(ref)) > 0.99) ref.set(1, 0, 0);
    const east = new THREE.Vector3().crossVectors(normal, ref).normalize();
    return new THREE.Vector3().crossVectors(east, normal).normalize();
  }

  /**
   * Parallel-transport this._north from oldNormal to newNormal.
   * Keeps the tangent vector smooth as the drone glides across the sphere.
   */
  _transportNorth(oldNormal, newNormal) {
    const angle = oldNormal.angleTo(newNormal);
    if (angle < 1e-8) return; // no movement

    // Rotation axis = cross(old, new), normalised
    const axis = new THREE.Vector3().crossVectors(oldNormal, newNormal);
    if (axis.lengthSq() < 1e-12) return; // parallel / anti-parallel
    axis.normalize();

    const q = new THREE.Quaternion().setFromAxisAngle(axis, angle);
    this._north.applyQuaternion(q);

    // Re-orthogonalise against the new normal to prevent drift
    this._north.addScaledVector(newNormal, -this._north.dot(newNormal)).normalize();
  }

  flyTo(point) {
    this._targetSurfacePoint.copy(point).normalize();
    this._isFlying = true;
  }

  setPosition(surfacePoint, height, orbitAngle, orbitTilt) {
    const oldN = this._surfacePoint.clone();
    this._surfacePoint.copy(surfacePoint).normalize();
    this._targetSurfacePoint.copy(this._surfacePoint);
    this._transportNorth(oldN, this._surfacePoint);
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

  restoreFromCameraPos(x, y, z) {
    const pos = new THREE.Vector3(x, y, z);
    const dist = pos.length();
    if (dist < 0.01) return;
    this._surfacePoint.copy(pos).normalize();
    this._targetSurfacePoint.copy(this._surfacePoint);
    this._north = this._initNorth(this._surfacePoint);
    this.height = Math.max(this.minHeight, Math.min(this.maxHeight, dist - 1.0));
    this.targetHeight = this.height;
    this._applyCameraPosition();
  }

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
    const orbitDiff = this._targetOrbitAngle - this._orbitAngle;
    if (Math.abs(orbitDiff) > 0.0001) {
      this._orbitAngle += orbitDiff * Math.min(1.0, this._orbitSpeed * t);
    } else {
      this._orbitAngle = this._targetOrbitAngle;
    }

    // Interpolate orbit tilt
    const tiltDiff = this._targetOrbitTilt - this._orbitTilt;
    if (Math.abs(tiltDiff) > 0.0001) {
      this._orbitTilt += tiltDiff * Math.min(1.0, this._orbitSpeed * t);
    } else {
      this._orbitTilt = this._targetOrbitTilt;
    }

    // Interpolate surface point via spherical lerp, parallel-transporting north
    const angle = this._surfacePoint.angleTo(this._targetSurfacePoint);
    if (angle > 0.001) {
      const oldN = this._surfacePoint.clone();
      const lerpFactor = Math.min(1.0, this._flySpeed * t);
      const fullQuat = new THREE.Quaternion().setFromUnitVectors(
        this._surfacePoint, this._targetSurfacePoint
      );
      const partialQuat = new THREE.Quaternion().slerpQuaternions(
        new THREE.Quaternion(), fullQuat, lerpFactor
      );
      this._surfacePoint.applyQuaternion(partialQuat).normalize();
      this._transportNorth(oldN, this._surfacePoint);
    } else {
      if (!this._surfacePoint.equals(this._targetSurfacePoint)) {
        const oldN = this._surfacePoint.clone();
        this._surfacePoint.copy(this._targetSurfacePoint);
        this._transportNorth(oldN, this._surfacePoint);
      }
      this._isFlying = false;
    }

    this._applyCameraPosition();
  }

  /**
   * Apply the current state to the actual camera transform.
   */
  _applyCameraPosition() {
    const normal = this._surfacePoint;

    // Camera always sits directly above the surface point.
    const camDist = 1.0 + this.height;
    this.camera.position.copy(normal).multiplyScalar(camDist);

    // Use the persistent, parallel-transported north as our tangent frame.
    // north = tangent pointing "up on screen" when tilt=0, orbit=0
    // east  = cross(normal, north) — tangent pointing "right"
    const north = this._north;
    const east = new THREE.Vector3().crossVectors(normal, north).normalize();

    // Orbit + tilt only rotate where the camera LOOKS.
    // Build the look offset in the tangent plane using orbit angle + tilt magnitude.
    const sinOrb = Math.sin(this._orbitAngle);
    const cosOrb = Math.cos(this._orbitAngle);
    const lookOffset = new THREE.Vector3()
      .addScaledVector(east, sinOrb * this._orbitTilt)
      .addScaledVector(north, cosOrb * this._orbitTilt);

    const lookTarget = new THREE.Vector3().copy(normal).add(lookOffset);

    // Build camera orientation manually (avoids lookAt degeneracy).
    const forward = new THREE.Vector3()
      .subVectors(lookTarget, this.camera.position).normalize();

    // "Screen up" = the orbit direction rotated 180° (behind the look direction).
    // This gives a stable, predictable up vector at every tilt including straight down.
    //
    // When tilt ≈ 0, forward ≈ -normal.  We want the top of the screen to point
    // in the direction the orbit angle "faces" — i.e. the orbit direction itself.
    const orbitDir = new THREE.Vector3()
      .addScaledVector(east, sinOrb)
      .addScaledVector(north, cosOrb)
      .normalize();

    // Gram-Schmidt: project orbitDir perpendicular to forward
    let up = orbitDir.clone();
    up.addScaledVector(forward, -up.dot(forward));

    if (up.lengthSq() < 1e-6) {
      // Fallback (shouldn't happen, but safety)
      up.copy(north);
      up.addScaledVector(forward, -up.dot(forward));
    }
    up.normalize();

    const right = new THREE.Vector3().crossVectors(forward, up).normalize();

    // THREE.js camera looks down local -Z, +Y up, +X right.
    const m = new THREE.Matrix4().makeBasis(right, up, forward.clone().negate());
    this.camera.quaternion.setFromRotationMatrix(m);
  }

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
    const step = 0.05 + this.targetHeight * 0.08;
    this.targetHeight = Math.max(
      this.minHeight,
      Math.min(this.maxHeight, this.targetHeight + delta * step)
    );
  }

  _handlePointerDown(event) {
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

  getState() {
    return {
      sx: this._surfacePoint.x,
      sy: this._surfacePoint.y,
      sz: this._surfacePoint.z,
      nx: this._north.x,
      ny: this._north.y,
      nz: this._north.z,
      height: this.height,
      orbit: this._orbitAngle,
      tilt: this._orbitTilt,
    };
  }

  restoreState(state) {
    if (state.sx != null) {
      this._surfacePoint.set(state.sx, state.sy, state.sz).normalize();
      this._targetSurfacePoint.copy(this._surfacePoint);
    }
    if (state.nx != null) {
      this._north.set(state.nx, state.ny, state.nz).normalize();
      // Re-orthogonalise against normal
      this._north.addScaledVector(this._surfacePoint, -this._north.dot(this._surfacePoint)).normalize();
    } else {
      this._north = this._initNorth(this._surfacePoint);
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
