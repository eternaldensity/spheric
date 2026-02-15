/**
 * BlueprintTool handles capture, stamp, preview, and persistence of building blueprints.
 */
export class BlueprintTool {
  constructor(chunkManager, pathfinding) {
    this.chunkManager = chunkManager;
    this.pathfinding = pathfinding;
    this.previewTiles = [];
    this.savedBlueprints = this._load();
  }

  _load() {
    try {
      const raw = localStorage.getItem("spheric_blueprints");
      return raw ? JSON.parse(raw) : [];
    } catch (_e) {
      return [];
    }
  }

  _save() {
    try {
      localStorage.setItem("spheric_blueprints", JSON.stringify(this.savedBlueprints));
    } catch (_e) { /* localStorage unavailable */ }
  }

  /**
   * Handle a click in blueprint mode.
   * Returns { action, data } or null if not handled.
   */
  onClick(tile, mode, captureStart, pattern, buildingData, pushEvent) {
    if (mode === "capture") {
      return this._handleCapture(tile, captureStart, buildingData, pushEvent);
    }
    if (mode === "stamp" && pattern) {
      this._handleStamp(tile, pattern, pushEvent);
      return { action: "stamped" };
    }
    return null;
  }

  _handleCapture(tile, captureStart, buildingData, pushEvent) {
    if (!captureStart) {
      this.chunkManager.setTileOverlay(tile.face, tile.row, tile.col, "selected");
      return { action: "capture_start", tile };
    }

    // Second click: capture rectangle on same face
    if (captureStart.face !== tile.face) {
      this.chunkManager.setTileOverlay(captureStart.face, captureStart.row, captureStart.col, null);
      return { action: "capture_reset" };
    }

    const minRow = Math.min(captureStart.row, tile.row);
    const maxRow = Math.max(captureStart.row, tile.row);
    const minCol = Math.min(captureStart.col, tile.col);
    const maxCol = Math.max(captureStart.col, tile.col);

    const pattern = [];
    for (let r = minRow; r <= maxRow; r++) {
      for (let c = minCol; c <= maxCol; c++) {
        const key = `${captureStart.face}:${r}:${c}`;
        const data = buildingData.get(key);
        if (data) {
          pattern.push({
            dr: r - minRow,
            dc: c - minCol,
            type: data.type,
            orientation: data.orientation,
          });
        }
      }
    }

    this.chunkManager.setTileOverlay(captureStart.face, captureStart.row, captureStart.col, null);

    if (pattern.length === 0) {
      return { action: "capture_empty" };
    }

    const name = `Blueprint ${this.savedBlueprints.length + 1} (${pattern.length} buildings)`;
    this.savedBlueprints.push({ name, pattern });
    this._save();

    pushEvent("blueprint_captured", {
      name,
      count: pattern.length,
      index: this.savedBlueprints.length - 1,
    });

    return { action: "captured", pattern };
  }

  _handleStamp(tile, pattern, pushEvent) {
    if (!pattern || pattern.length === 0) return;

    const buildings = [];
    for (const entry of pattern) {
      let current = { face: tile.face, row: tile.row, col: tile.col };

      for (let i = 0; i < entry.dr; i++) {
        const next = this.pathfinding.getNeighborTile(current, 1);
        if (!next) { current = null; break; }
        current = next;
      }
      if (!current) continue;

      for (let i = 0; i < entry.dc; i++) {
        const next = this.pathfinding.getNeighborTile(current, 0);
        if (!next) { current = null; break; }
        current = next;
      }
      if (!current) continue;

      buildings.push({
        face: current.face,
        row: current.row,
        col: current.col,
        orientation: entry.orientation,
        type: entry.type,
      });
    }

    if (buildings.length > 0) {
      pushEvent("place_blueprint", { buildings });
    }
  }

  showPreview(tile, pattern) {
    this.clearPreview();
    if (!pattern) return;

    for (const entry of pattern) {
      let current = { face: tile.face, row: tile.row, col: tile.col };

      for (let i = 0; i < entry.dr; i++) {
        const next = this.pathfinding.getNeighborTile(current, 1);
        if (!next) { current = null; break; }
        current = next;
      }
      if (!current) continue;

      for (let i = 0; i < entry.dc; i++) {
        const next = this.pathfinding.getNeighborTile(current, 0);
        if (!next) { current = null; break; }
        current = next;
      }
      if (!current) continue;

      this.chunkManager.setTileOverlay(current.face, current.row, current.col, "hover");
      this.previewTiles.push(current);
    }
  }

  clearPreview() {
    for (const tile of this.previewTiles) {
      const overlay = this.chunkManager.getTileOverlay(tile.face, tile.row, tile.col);
      if (overlay === "hover") {
        this.chunkManager.setTileOverlay(tile.face, tile.row, tile.col, null);
      }
    }
    this.previewTiles = [];
  }

  selectBlueprint(index) {
    const bp = this.savedBlueprints[index];
    return bp ? bp.pattern : null;
  }

  deleteBlueprint(index) {
    if (index >= 0 && index < this.savedBlueprints.length) {
      this.savedBlueprints.splice(index, 1);
      this._save();
    }
  }

  dispose() {
    this.clearPreview();
  }
}
