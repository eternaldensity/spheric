import * as THREE from "three";

/**
 * PlayerPresence renders multiplayer player markers on the sphere surface.
 */
export class PlayerPresence {
  constructor(scene) {
    this.scene = scene;
    this.markers = new Map(); // name -> { group, sphere, label }
  }

  update(players) {
    const activeNames = new Set();

    for (const p of players) {
      activeNames.add(p.name);
      const cameraPos = new THREE.Vector3(p.x, p.y, p.z);
      const surfacePoint = cameraPos.clone().normalize();

      let marker = this.markers.get(p.name);
      if (!marker) {
        marker = this._createMarker(p.name, p.color);
        this.markers.set(p.name, marker);
        this.scene.add(marker.group);
      }

      marker.group.position.copy(surfacePoint).multiplyScalar(1.01);
      marker.group.lookAt(surfacePoint.clone().multiplyScalar(2));
    }

    // Remove markers for players who left
    for (const [name, marker] of this.markers) {
      if (!activeNames.has(name)) {
        this.scene.remove(marker.group);
        marker.label.material.map.dispose();
        marker.label.material.dispose();
        marker.sphere.material.dispose();
        marker.sphere.geometry.dispose();
        this.markers.delete(name);
      }
    }
  }

  _createMarker(name, color) {
    const group = new THREE.Group();

    const sphereGeo = new THREE.SphereGeometry(0.006, 8, 8);
    const sphereMat = new THREE.MeshBasicMaterial({ color: new THREE.Color(color) });
    const sphere = new THREE.Mesh(sphereGeo, sphereMat);
    group.add(sphere);

    const canvas = document.createElement("canvas");
    canvas.width = 128;
    canvas.height = 32;
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = color;
    ctx.font = "bold 18px monospace";
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(name, 64, 16);

    const texture = new THREE.CanvasTexture(canvas);
    texture.minFilter = THREE.LinearFilter;
    const spriteMat = new THREE.SpriteMaterial({ map: texture, transparent: true });
    const label = new THREE.Sprite(spriteMat);
    label.scale.set(0.03, 0.008, 1);
    label.position.set(0, 0.01, 0);
    group.add(label);

    return { group, sphere, label };
  }

  dispose() {
    for (const [, marker] of this.markers) {
      this.scene.remove(marker.group);
      marker.label.material.map.dispose();
      marker.label.material.dispose();
      marker.sphere.material.dispose();
      marker.sphere.geometry.dispose();
    }
    this.markers.clear();
  }
}
