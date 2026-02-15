import * as THREE from "three";

// Direction offsets: orientation -> [dRow, dCol]
// 0=W (col+1), 1=S (row+1), 2=E (col-1), 3=N (row-1)
const DIR_OFFSETS = [
  [0, 1],   // W
  [1, 0],   // S
  [0, -1],  // E
  [-1, 0],  // N
];

/**
 * PathfindingEngine handles cross-face neighbor resolution and greedy
 * line-path computation on the rhombic triacontahedron.
 */
export class PathfindingEngine {
  constructor(faceIndices, subdivisions, getTileCenter) {
    this.faceIndices = faceIndices;
    this.subdivisions = subdivisions;
    this.getTileCenter = getTileCenter;
    this.adjacencyMap = this._buildAdjacencyMap();
  }

  _buildAdjacencyMap() {
    const faces = this.faceIndices;
    const edgeToFaces = new Map();

    for (let faceId = 0; faceId < faces.length; faceId++) {
      const [v0, v1, v2, v3] = faces[faceId];
      const edges = [[v0, v1], [v1, v2], [v2, v3], [v3, v0]];

      for (let edgeIdx = 0; edgeIdx < 4; edgeIdx++) {
        const [a, b] = edges[edgeIdx];
        const edgeKey = Math.min(a, b) * 10000 + Math.max(a, b);
        if (!edgeToFaces.has(edgeKey)) edgeToFaces.set(edgeKey, []);
        edgeToFaces.get(edgeKey).push({ faceId, edgeIdx, verts: [a, b] });
      }
    }

    const adjacency = [];
    for (let faceId = 0; faceId < faces.length; faceId++) {
      const [v0, v1, v2, v3] = faces[faceId];
      const edges = [[v0, v1], [v1, v2], [v2, v3], [v3, v0]];
      const neighbors = [];

      for (let edgeIdx = 0; edgeIdx < 4; edgeIdx++) {
        const [a, b] = edges[edgeIdx];
        const edgeKey = Math.min(a, b) * 10000 + Math.max(a, b);
        const entries = edgeToFaces.get(edgeKey);
        const other = entries.find(e => e.faceId !== faceId);

        if (other) {
          const theirVerts = other.verts;
          const flipped = (a === theirVerts[1] && b === theirVerts[0]);
          neighbors.push({ face: other.faceId, theirEdge: other.edgeIdx, flipped });
        } else {
          neighbors.push(null);
        }
      }
      adjacency.push(neighbors);
    }
    return adjacency;
  }

  getNeighborTile(tile, direction) {
    const N = this.subdivisions;
    const { face, row, col } = tile;
    const [dr, dc] = DIR_OFFSETS[direction];
    const newRow = row + dr;
    const newCol = col + dc;

    if (newRow >= 0 && newRow < N && newCol >= 0 && newCol < N) {
      return { face, row: newRow, col: newCol };
    }
    return this._crossFaceNeighbor(face, row, col, direction);
  }

  _crossFaceNeighbor(face, row, col, direction) {
    const max = this.subdivisions - 1;

    let myEdge, posAlongEdge;
    switch (direction) {
      case 0: myEdge = 1; posAlongEdge = row; break;
      case 1: myEdge = 2; posAlongEdge = max - col; break;
      case 2: myEdge = 3; posAlongEdge = max - row; break;
      case 3: myEdge = 0; posAlongEdge = col; break;
    }

    const neighborInfo = this.adjacencyMap[face][myEdge];
    if (!neighborInfo) return null;

    const pos = neighborInfo.flipped ? max - posAlongEdge : posAlongEdge;

    let newRow, newCol;
    switch (neighborInfo.theirEdge) {
      case 0: newRow = 0; newCol = pos; break;
      case 1: newRow = pos; newCol = max; break;
      case 2: newRow = max; newCol = max - pos; break;
      case 3: newRow = max - pos; newCol = 0; break;
    }

    return { face: neighborInfo.face, row: newRow, col: newCol };
  }

  bestDirectionToward(tile, targetPos) {
    let bestDir = 0;
    let bestDist = Infinity;

    for (let dir = 0; dir < 4; dir++) {
      const [dr, dc] = DIR_OFFSETS[dir];
      const neighborPos = this.getTileCenter(tile.face, tile.row + dr, tile.col + dc);
      const dist = neighborPos.distanceToSquared(targetPos);
      if (dist < bestDist) {
        bestDist = dist;
        bestDir = dir;
      }
    }
    return bestDir;
  }

  computeLinePath(start, end, placementOrientation) {
    const MAX_LINE_LENGTH = 128;
    const path = [];
    const visited = new Set();

    let current = { face: start.face, row: start.row, col: start.col };
    const targetPos = this.getTileCenter(end.face, end.row, end.col);

    // Special case: start == end, place single tile with current orientation
    if (start.face === end.face && start.row === end.row && start.col === end.col) {
      return [{ ...current, orientation: placementOrientation }];
    }

    for (let step = 0; step < MAX_LINE_LENGTH; step++) {
      const key = `${current.face}:${current.row}:${current.col}`;
      if (visited.has(key)) break;
      visited.add(key);

      const isTarget =
        current.face === end.face &&
        current.row === end.row &&
        current.col === end.col;

      if (isTarget) {
        const prevOrientation = path.length > 0
          ? path[path.length - 1].orientation
          : placementOrientation;
        path.push({ ...current, orientation: prevOrientation });
        break;
      }

      const bestDir = this.bestDirectionToward(current, targetPos);
      path.push({ ...current, orientation: bestDir });

      const neighbor = this.getNeighborTile(current, bestDir);
      if (!neighbor) break;
      current = neighbor;
    }

    return path;
  }
}
