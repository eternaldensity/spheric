/**
 * DemolishTool manages the demolish area preview overlays.
 */
export class DemolishTool {
  constructor(chunkManager) {
    this.chunkManager = chunkManager;
    this.previewTiles = [];
  }

  showPreview(demolishStart, endTile, buildingData) {
    this.clearPreview();

    if (!demolishStart || demolishStart.face !== endTile.face) return;

    const start = demolishStart;
    const minRow = Math.min(start.row, endTile.row);
    const maxRow = Math.max(start.row, endTile.row);
    const minCol = Math.min(start.col, endTile.col);
    const maxCol = Math.max(start.col, endTile.col);

    for (let r = minRow; r <= maxRow; r++) {
      for (let c = minCol; c <= maxCol; c++) {
        const key = `${start.face}:${r}:${c}`;
        const hasBuilding = buildingData.has(key);
        this.previewTiles.push({ face: start.face, row: r, col: c, hasBuilding });
        this.chunkManager.setTileOverlay(start.face, r, c, hasBuilding ? "demolish" : "hover");
      }
    }
  }

  clearPreview() {
    for (const tile of this.previewTiles) {
      const overlay = this.chunkManager.getTileOverlay(tile.face, tile.row, tile.col);
      if (overlay === "demolish" || overlay === "hover") {
        this.chunkManager.setTileOverlay(tile.face, tile.row, tile.col, null);
      }
    }
    this.previewTiles = [];
  }

  /** Cancel demolish draw: clear preview and start marker overlay. */
  cancel(demolishStart) {
    this.clearPreview();
    if (demolishStart) {
      const overlay = this.chunkManager.getTileOverlay(
        demolishStart.face, demolishStart.row, demolishStart.col
      );
      if (overlay === "selected") {
        this.chunkManager.setTileOverlay(
          demolishStart.face, demolishStart.row, demolishStart.col, null
        );
      }
    }
  }

  dispose() {
    this.clearPreview();
  }
}
