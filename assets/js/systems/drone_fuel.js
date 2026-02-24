/**
 * DroneFuelSystem — client-side fuel management for the camera drone.
 *
 * Fuel state is stored in localStorage. Ground item pickup is validated
 * server-side via pushEvent("pickup_fuel", ...).
 *
 * Tank: 5 slots (default), expandable to 10 with upgrade.
 * Biofuel: 60s real-time per unit.
 * Refined fuel: 150s real-time per unit.
 * Out of fuel: low power mode (25% movement speed).
 */

const STORAGE_KEY = "spheric_drone_fuel";
const BASE_CAPACITY = 5;
const BIOFUEL_DURATION = 60;
const REFINED_FUEL_DURATION = 150;
const LOW_POWER_SPEED = 0.25;
const NORMAL_SPEED = 1.0;
const PICKUP_COOLDOWN_MS = 1500;

export class DroneFuelSystem {
  constructor(pushEventFn) {
    this._pushEvent = pushEventFn;

    const saved = this._load();
    this._tank = saved.tank;
    this._currentFuel = saved.current;
    this._capacityBonus = saved.capacityBonus || 0;
    this._autoRefuel = saved.autoRefuel || false;
    this._spotlightUnlocked = saved.spotlightUnlocked || false;
    this._spotlightOn = false;

    // Cargo (item pickup/drop)
    this._cargo = saved.cargo || [];
    this._cargoCapacity = saved.cargoCapacity || 1;

    this._lowPower = false;
    this._lastPickupAttempt = 0;
    this._lastCargoPickupAttempt = 0;
    this._saveTimer = 0;

    /** @type {((isLowPower: boolean) => void) | null} */
    this.onLowPowerChange = null;
    /** @type {(() => void) | null} */
    this.onFuelChange = null;
  }

  get capacity() {
    return BASE_CAPACITY + this._capacityBonus;
  }

  get tankCount() {
    return this._tank.length + (this._currentFuel ? 1 : 0);
  }

  get isLowPower() {
    return this._lowPower;
  }

  get speedMultiplier() {
    return this._lowPower ? LOW_POWER_SPEED : NORMAL_SPEED;
  }

  get spotlightOn() {
    return this._spotlightOn;
  }

  get spotlightUnlocked() {
    return this._spotlightUnlocked;
  }

  /**
   * Called every frame from the animate loop. dt is in seconds.
   * @param {number} dt - frame delta in seconds
   * @param {object} [droneState] - { isMoving, height }
   */
  update(dt, droneState) {
    let burnRate = this._spotlightOn ? dt * 2 : dt;

    if (droneState && !droneState.isMoving) {
      // Parked near the ground: no fuel burn
      if (droneState.height < 0.1) {
        burnRate = 0;
      } else {
        // Hovering stationary: half burn
        burnRate *= 0.5;
      }
    }

    if (this._currentFuel) {
      this._currentFuel.remaining -= burnRate;

      if (this._currentFuel.remaining <= 0) {
        this._currentFuel = null;
        this._loadNextFuel();
        this._dirtySave();
        this._notifyFuelChange();
      } else {
        // Periodic save (every ~5 seconds)
        this._saveTimer += dt;
        if (this._saveTimer > 5) {
          this._saveTimer = 0;
          this._save();
        }
      }
    } else {
      // No current fuel — try loading from tank
      if (this._tank.length > 0) {
        this._loadNextFuel();
        this._dirtySave();
        this._notifyFuelChange();
      } else {
        // Out of fuel — low power
        if (!this._lowPower) {
          this._lowPower = true;
          if (this.onLowPowerChange) this.onLowPowerChange(true);
        }
        return;
      }
    }

    if (this._lowPower) {
      this._lowPower = false;
      if (this.onLowPowerChange) this.onLowPowerChange(false);
    }
  }

  /**
   * Attempt to pick up fuel from a ground tile. Called when zoomed close.
   */
  tryPickup(face, row, col) {
    const now = performance.now();
    if (now - this._lastPickupAttempt < PICKUP_COOLDOWN_MS) return;
    if (this.tankCount >= this.capacity) return;

    this._lastPickupAttempt = now;
    this._pushEvent("pickup_fuel", { face, row, col });
  }

  /**
   * Handle server response to pickup request.
   */
  onPickupResult({ success, item }) {
    if (!success) return;

    if (!this._currentFuel) {
      this._currentFuel = {
        type: item,
        remaining: this._fuelDuration(item),
      };
    } else if (this._tank.length < this.capacity - 1) {
      this._tank.push(item);
    }

    this._dirtySave();
    this._notifyFuelChange();
  }

  /**
   * Attempt to pick up any ground item from a tile. Called when drone is low.
   */
  tryPickupItem(face, row, col) {
    if (this._cargo.length >= this._cargoCapacity) return;
    const now = performance.now();
    if (now - this._lastCargoPickupAttempt < PICKUP_COOLDOWN_MS) return;
    this._lastCargoPickupAttempt = now;
    this._pushEvent("drone_pickup_item", { face, row, col });
  }

  /**
   * Handle server response to item pickup request.
   */
  onItemPickupResult({ success, item }) {
    if (!success) return;
    if (this._cargo.length < this._cargoCapacity) {
      this._cargo.push(item);
      this._dirtySave();
      this._notifyFuelChange();
    }
  }

  /**
   * Drop the first cargo item. Returns the item type string, or null if empty.
   */
  dropItem() {
    if (this._cargo.length === 0) return null;
    const item = this._cargo.shift();
    this._dirtySave();
    this._notifyFuelChange();
    return item;
  }

  /**
   * Returns cargo data for HUD rendering.
   */
  getCargoData() {
    return { items: [...this._cargo], capacity: this._cargoCapacity };
  }

  /**
   * Handle server granting a drone upgrade.
   */
  onUpgradeGranted(upgrade) {
    if (upgrade === "expanded_tank") this._capacityBonus = 5;
    if (upgrade === "auto_refuel") this._autoRefuel = true;
    if (upgrade === "drone_spotlight") this._spotlightUnlocked = true;
    if (upgrade === "expanded_cargo") this._cargoCapacity = 4;
    this._dirtySave();
    this._notifyFuelChange();
  }

  toggleSpotlight() {
    if (!this._spotlightUnlocked) return;
    this._spotlightOn = !this._spotlightOn;
  }

  /**
   * Instantly drain the given number of seconds from current fuel.
   * Spills over into reserve tank if the active cell is exhausted.
   */
  drain(seconds) {
    let remaining = seconds;
    while (remaining > 0 && this._currentFuel) {
      if (this._currentFuel.remaining > remaining) {
        this._currentFuel.remaining -= remaining;
        remaining = 0;
      } else {
        remaining -= this._currentFuel.remaining;
        this._currentFuel = null;
        this._loadNextFuel();
      }
    }
    this._dirtySave();
    this._notifyFuelChange();
  }

  /**
   * Initialize from localStorage. On first visit, fill tank with biofuel.
   */
  initFromStorage() {
    if (this._tank === null) {
      this._tank = [];
      this._currentFuel = {
        type: "biofuel",
        remaining: BIOFUEL_DURATION,
      };
      for (let i = 0; i < BASE_CAPACITY - 1; i++) {
        this._tank.push("biofuel");
      }
      this._save();
    }
  }

  /**
   * Returns data for the HUD fuel gauge.
   */
  getGaugeData() {
    const slots = [];

    // Reserve (full) pips first on the left
    for (const t of this._tank) {
      slots.push({ type: t, fraction: 1.0, active: false });
    }

    // Active (draining) pip next
    if (this._currentFuel) {
      slots.push({
        type: this._currentFuel.type,
        fraction: this._currentFuel.remaining / this._fuelDuration(this._currentFuel.type),
        active: true,
      });
    }

    // Empty slots on the right
    while (slots.length < this.capacity) slots.push(null);

    return { slots, lowPower: this._lowPower };
  }

  // --- Private ---

  _loadNextFuel() {
    if (this._tank.length > 0) {
      const next = this._tank.shift();
      this._currentFuel = {
        type: next,
        remaining: this._fuelDuration(next),
      };
    }
  }

  _fuelDuration(type) {
    return type === "refined_fuel" ? REFINED_FUEL_DURATION : BIOFUEL_DURATION;
  }

  _dirtySave() {
    this._saveTimer = 0;
    this._save();
  }

  _save() {
    try {
      localStorage.setItem(
        STORAGE_KEY,
        JSON.stringify({
          tank: this._tank,
          current: this._currentFuel,
          capacityBonus: this._capacityBonus,
          autoRefuel: this._autoRefuel,
          spotlightUnlocked: this._spotlightUnlocked,
          cargo: this._cargo,
          cargoCapacity: this._cargoCapacity,
        })
      );
    } catch (_e) {
      /* localStorage unavailable */
    }
  }

  _load() {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) {
        return {
          tank: null,
          current: null,
          capacityBonus: 0,
          autoRefuel: false,
          spotlightUnlocked: false,
          cargo: [],
          cargoCapacity: 1,
        };
      }
      const data = JSON.parse(raw);
      return {
        tank: data.tank,
        current: data.current,
        capacityBonus: data.capacityBonus || 0,
        autoRefuel: data.autoRefuel || false,
        spotlightUnlocked: data.spotlightUnlocked || false,
        cargo: data.cargo || [],
        cargoCapacity: data.cargoCapacity || 1,
      };
    } catch (_e) {
      return {
        tank: null,
        current: null,
        capacityBonus: 0,
        autoRefuel: false,
        spotlightUnlocked: false,
        cargo: [],
        cargoCapacity: 1,
      };
    }
  }

  _notifyFuelChange() {
    if (this.onFuelChange) this.onFuelChange();
  }
}
