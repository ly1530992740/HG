// Survival/Shop：商品目录和购买服务，不直接实现具体武器或友军逻辑。
import { EventTarget } from 'cc';
import { SurvivalEconomy } from './Economy';

export interface ShopItem { id: string; price: number; kind: 'weapon' | 'ally' | 'supply'; payload: Record<string, number | string>; }
export const DEFAULT_SHOP: ShopItem[] = [
  { id: 'smg', price: 8, kind: 'weapon', payload: { weapon: 'smg', ammo: 30 } },
  { id: 'ally', price: 12, kind: 'ally', payload: { population: 1 } },
  { id: 'medical_pack', price: 5, kind: 'supply', payload: { medical: 4 } },
];
export class ShopService {
  readonly events = new EventTarget();
  constructor(public economy: SurvivalEconomy, public items = DEFAULT_SHOP) {}
  purchase(id: string): ShopItem | null {
    const item = this.items.find((entry) => entry.id === id);
    if (!item || !this.economy.spend(item.price)) return null;
    this.events.emit('purchased', item); return item;
  }
}
