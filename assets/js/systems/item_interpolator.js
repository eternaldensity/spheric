/**
 * ItemInterpolator manages smooth client-side movement of items between server ticks.
 *
 * On each server tick (every 200ms), the server sends the complete item state per face.
 * The interpolator lerps item positions from their previous location to their current
 * location over the tick interval, producing smooth 60fps visuals.
 */

const TICK_INTERVAL = 200; // ms, must match server @tick_interval_ms

export class ItemInterpolator {
  constructor() {
    // Current tick items keyed by "face:row:col"
    this.currItems = new Map();
    this.tickStartTime = 0;
    this.tickInterval = TICK_INTERVAL;
  }

  /**
   * Called when a tick_items event arrives from the server.
   * Replaces items for the given face with the new snapshot.
   */
  onTickUpdate(tick, face, items) {
    // Remove old items on this face
    for (const [key, val] of this.currItems) {
      if (val.face === face) {
        this.currItems.delete(key);
      }
    }

    // Add new items
    for (const item of items) {
      const key = `${face}:${item.row}:${item.col}`;
      this.currItems.set(key, {
        face: face,
        row: item.row,
        col: item.col,
        item: item.item,
        fromFace: item.from_face,
        fromRow: item.from_row,
        fromCol: item.from_col,
      });
    }

    this.tickStartTime = performance.now();
  }

  /**
   * Returns interpolated item positions for the current frame.
   * Called every frame (60fps) from the render loop.
   *
   * @param {number} now - performance.now() timestamp
   * @returns {Array<{face, row, col, fromFace, fromRow, fromCol, item, t}>}
   */
  getInterpolatedItems(now) {
    const elapsed = now - this.tickStartTime;
    const t = Math.min(elapsed / this.tickInterval, 1.0);

    const result = [];

    for (const [, curr] of this.currItems) {
      if (curr.fromFace != null && curr.fromRow != null && curr.fromCol != null) {
        // Item moved this tick — interpolate from source to destination
        result.push({
          face: curr.face,
          row: curr.row,
          col: curr.col,
          fromFace: curr.fromFace,
          fromRow: curr.fromRow,
          fromCol: curr.fromCol,
          item: curr.item,
          t: t,
        });
      } else {
        // Item is stationary
        result.push({
          face: curr.face,
          row: curr.row,
          col: curr.col,
          fromFace: null,
          fromRow: null,
          fromCol: null,
          item: curr.item,
          t: 1.0,
        });
      }
    }

    return result;
  }
}
