/**
 * ItemInterpolator manages smooth client-side movement of items between server ticks.
 *
 * On each server tick (every 200ms), the server sends the complete item state per face.
 * The interpolator lerps item positions from their previous location to their current
 * location over the tick interval, producing smooth 60fps visuals.
 *
 * Different conduit tiers move at different speeds:
 *   Mk-III: 1 tick (200ms) per tile — speed: 1
 *   Mk-II:  2 ticks (400ms) per tile — speed: 2
 *   Mk-I:   3 ticks (600ms) per tile — speed: 3
 *
 * Tick start times are tracked per-face so that updates arriving for one face
 * don't reset the interpolation progress of items on other faces.
 */

const TICK_INTERVAL = 200; // ms, must match server @tick_interval_ms

export class ItemInterpolator {
  constructor() {
    // Current tick items keyed by "face:row:col"
    this.currItems = new Map();
    // Per-face tick start times so cross-face updates don't interfere
    this.faceTickStart = new Map(); // face -> performance.now() timestamp
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
        speed: item.speed || 1,
        fromFace: item.from_face,
        fromRow: item.from_row,
        fromCol: item.from_col,
      });
    }

    if (items.length > 0) {
      this.faceTickStart.set(face, performance.now());
    } else {
      this.faceTickStart.delete(face);
    }
  }

  /**
   * Returns interpolated item positions for the current frame.
   * Called every frame (60fps) from the render loop.
   *
   * @param {number} now - performance.now() timestamp
   * @returns {Array<{face, row, col, fromFace, fromRow, fromCol, item, t}>}
   */
  getInterpolatedItems(now) {
    const result = [];

    for (const [, curr] of this.currItems) {
      if (curr.fromFace != null && curr.fromRow != null && curr.fromCol != null) {
        // Item moved this tick — interpolate using the face's own tick start.
        // Slower belts spread the lerp over multiple tick intervals for smooth glide.
        const start = this.faceTickStart.get(curr.face) || 0;
        const elapsed = now - start;
        const lerpDuration = (curr.speed || 1) * this.tickInterval;
        const t = Math.min(elapsed / lerpDuration, 1.0);

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
