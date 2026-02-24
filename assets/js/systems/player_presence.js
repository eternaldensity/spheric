import * as THREE from "three";

const S = 0.0075; // Match BUILDING_SCALE from building_factory

// Shared geometries for all drone markers (created once, never disposed)
const _sharedGeo = {
  body: new THREE.BoxGeometry(S * 0.7, S * 0.25, S * 0.7),
  arm: new THREE.BoxGeometry(S * 1.1, S * 0.08, S * 0.1),
  rotor: new THREE.CylinderGeometry(S * 0.35, S * 0.35, S * 0.04, 8),
  motor: new THREE.CylinderGeometry(S * 0.1, S * 0.12, S * 0.15, 6),
  camera: new THREE.SphereGeometry(S * 0.12, 6, 6),
  skid: new THREE.BoxGeometry(S * 0.08, S * 0.12, S * 0.6),
};
for (const geo of Object.values(_sharedGeo)) geo._shared = true;

const _darkMat = new THREE.MeshLambertMaterial({ color: 0x333340 });
_darkMat._shared = true;
const _rotorMat = new THREE.MeshLambertMaterial({
  color: 0xaabbcc,
  transparent: true,
  opacity: 0.5,
});
_rotorMat._shared = true;
const _cameraMat = new THREE.MeshLambertMaterial({ color: 0x222222 });
_cameraMat._shared = true;

// Interpolation speed — higher = snappier, lower = smoother
const LERP_SPEED = 5;

/**
 * PlayerPresence renders other players as quadcopter drones on the sphere.
 */
export class PlayerPresence {
  constructor(scene) {
    this.scene = scene;
    this.markers = new Map(); // name -> { group, parts, label, target }
  }

  /** Called when server sends new player positions (every ~500ms). */
  update(players) {
    const activeNames = new Set();

    for (const p of players) {
      activeNames.add(p.name);
      const target = new THREE.Vector3(p.x, p.y, p.z);

      let marker = this.markers.get(p.name);
      if (!marker) {
        marker = this._createMarker(p.name, p.color);
        this.markers.set(p.name, marker);
        this.scene.add(marker.group);
        // First appearance — snap to position immediately
        this._applyPosition(marker, target);
      }

      marker.target = target;
    }

    // Remove markers for players who left
    for (const [name, marker] of this.markers) {
      if (!activeNames.has(name)) {
        this._disposeMarker(marker);
        this.markers.delete(name);
      }
    }
  }

  /** Called every frame from the render loop to smoothly interpolate positions. */
  tick(dt) {
    const alpha = 1 - Math.exp(-LERP_SPEED * dt);
    for (const [, marker] of this.markers) {
      if (!marker.target) continue;
      marker.group.position.lerp(marker.target, alpha);
      // Re-orient to face outward from sphere at current (interpolated) position
      const outward = marker.group.position.clone().normalize();
      marker.group.lookAt(
        outward.multiplyScalar(marker.group.position.length() + 1),
      );
    }
  }

  _applyPosition(marker, pos) {
    const surfaceDir = pos.clone().normalize();
    marker.group.position.copy(pos);
    marker.group.lookAt(surfaceDir.multiplyScalar(pos.length() + 1));
  }

  _createMarker(name, color) {
    const group = new THREE.Group();
    const accentMat = new THREE.MeshLambertMaterial({ color: new THREE.Color(color) });
    const parts = { accentMat };

    // Inner group rotated so the drone's Y-up becomes Z-outward after lookAt.
    // lookAt points local +Z outward from sphere; rotating -90° on X maps Y->Z.
    const drone = new THREE.Group();
    drone.rotation.x = -Math.PI / 2;
    group.add(drone);

    // Central body — player-colored
    const body = new THREE.Mesh(_sharedGeo.body, accentMat);
    body.position.y = S * 0.15;
    drone.add(body);

    // 4 diagonal arms + rotors + motors
    const armAngle = Math.PI / 4; // 45 degrees, so arms go to corners
    for (let i = 0; i < 4; i++) {
      const angle = armAngle + (Math.PI / 2) * i;

      // Arm
      const arm = new THREE.Mesh(_sharedGeo.arm, _darkMat);
      arm.position.set(
        Math.cos(angle) * S * 0.45,
        S * 0.15,
        Math.sin(angle) * S * 0.45,
      );
      arm.rotation.y = -angle;
      drone.add(arm);

      // Motor hub at arm tip
      const motor = new THREE.Mesh(_sharedGeo.motor, _darkMat);
      motor.position.set(
        Math.cos(angle) * S * 0.9,
        S * 0.23,
        Math.sin(angle) * S * 0.9,
      );
      drone.add(motor);

      // Rotor disc (translucent)
      const rotor = new THREE.Mesh(_sharedGeo.rotor, _rotorMat);
      rotor.position.set(
        Math.cos(angle) * S * 0.9,
        S * 0.32,
        Math.sin(angle) * S * 0.9,
      );
      drone.add(rotor);
    }

    // Camera/sensor pod underneath
    const cam = new THREE.Mesh(_sharedGeo.camera, _cameraMat);
    cam.position.y = S * -0.02;
    drone.add(cam);

    // Landing skids
    const skid1 = new THREE.Mesh(_sharedGeo.skid, _darkMat);
    skid1.position.set(S * -0.35, S * -0.06, 0);
    drone.add(skid1);
    const skid2 = new THREE.Mesh(_sharedGeo.skid, _darkMat);
    skid2.position.set(S * 0.35, S * -0.06, 0);
    drone.add(skid2);

    // Name label sprite — added to outer group so it stays screen-facing
    const canvas = document.createElement("canvas");
    canvas.width = 256;
    canvas.height = 48;
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = color;
    ctx.font = "bold 24px monospace";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(name, 128, 24);

    const texture = new THREE.CanvasTexture(canvas);
    texture.minFilter = THREE.LinearFilter;
    const spriteMat = new THREE.SpriteMaterial({ map: texture, transparent: true });
    const label = new THREE.Sprite(spriteMat);
    label.scale.set(0.03, 0.006, 1);
    // Label offset in outer group's local space — Z is outward from sphere after lookAt
    label.position.set(0, 0, S * 0.7);
    group.add(label);
    parts.label = label;

    return { group, parts };
  }

  _disposeMarker(marker) {
    this.scene.remove(marker.group);
    // Dispose per-player resources (accent material + label texture/material)
    marker.parts.accentMat.dispose();
    marker.parts.label.material.map.dispose();
    marker.parts.label.material.dispose();
    // Shared geometries and shared materials are NOT disposed
  }

  dispose() {
    for (const [, marker] of this.markers) {
      this._disposeMarker(marker);
    }
    this.markers.clear();
  }
}
