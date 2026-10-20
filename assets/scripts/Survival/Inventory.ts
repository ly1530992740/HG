// Survival/Inventory：槽位背包，负责堆叠、移除和容量拒绝事件。
import { EventTarget } from 'cc';

export interface ItemStack {
  type: string;
  amount: number;
  maxStack?: number;
}

/** Slot based inventory equivalent of InventoryComponent. */
export class Inventory {
  readonly events = new EventTarget();
  readonly stacks: Array<ItemStack | null>;
  constructor(public slots = 12, public defaultStackLimit = 20) {
    this.stacks = Array.from({ length: Math.max(1, slots) }, () => null);
  }

  addItem(item: ItemStack): number {
    if (!item?.type || item.amount <= 0) return 0;
    let remaining = Math.floor(item.amount);
    const limit = Math.max(1, item.maxStack || this.defaultStackLimit);
    for (let i = 0; i < this.stacks.length && remaining > 0; i++) {
      const stack = this.stacks[i];
      if (!stack || stack.type !== item.type) continue;
      const moved = Math.min(remaining, Math.max(0, (stack.maxStack || limit) - stack.amount));
      if (moved) { stack.amount += moved; remaining -= moved; this.events.emit('stack-changed', i, { ...stack }); }
    }
    for (let i = 0; i < this.stacks.length && remaining > 0; i++) {
      if (this.stacks[i]) continue;
      const moved = Math.min(remaining, limit);
      this.stacks[i] = { type: item.type, amount: moved, maxStack: limit };
      remaining -= moved;
      this.events.emit('stack-changed', i, { ...this.stacks[i]! });
    }
    if (remaining > 0) this.events.emit('pickup-rejected', { ...item }, remaining);
    return item.amount - remaining;
  }

  removeItem(type: string, amount: number): number {
    let remaining = Math.max(0, Math.floor(amount));
    let removed = 0;
    for (let i = this.stacks.length - 1; i >= 0 && remaining > 0; i--) {
      const stack = this.stacks[i];
      if (!stack || stack.type !== type) continue;
      const moved = Math.min(remaining, stack.amount);
      stack.amount -= moved; remaining -= moved; removed += moved;
      if (stack.amount <= 0) this.stacks[i] = null;
      this.events.emit('stack-changed', i, this.stacks[i] ? { ...this.stacks[i]! } : null);
    }
    return removed;
  }

  count(type?: string): number {
    return this.stacks.reduce((total, stack) => total + (stack && (!type || stack.type === type) ? stack.amount : 0), 0);
  }
}
