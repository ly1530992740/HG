// Survival/Construction：配方、成本、位置校验和建造进度。
import { EventTarget, Vec2 } from 'cc';
import { GameState, ResourceMap } from '../Core/GameState';
import { BuildingType } from '../Build/Building';
import { Durability } from './Durability';

export interface BuildingRecipe { type: BuildingType; cost: Partial<ResourceMap>; buildTime: number; workers: number; }
export interface PlacedBuilding { id: string; recipe: BuildingRecipe; position: Vec2; durability: Durability; progress: number; built: boolean; }

export const DEFAULT_RECIPES: Record<BuildingType, BuildingRecipe> = {
  farm: { type: 'farm', cost: { material: 20 }, buildTime: 3, workers: 1 },
  factory: { type: 'factory', cost: { material: 35 }, buildTime: 5, workers: 1 },
  medical: { type: 'medical', cost: { material: 30, medical: 1 }, buildTime: 4, workers: 1 },
  turret: { type: 'turret', cost: { material: 45, ammo: 5 }, buildTime: 6, workers: 0 },
};

export class ConstructionSystem {
  readonly events = new EventTarget();
  readonly buildings: PlacedBuilding[] = [];
  constructor(public state: GameState, public recipes = DEFAULT_RECIPES) {}
  canPlace(position: Vec2, radius = 45): boolean {
    return this.buildings.every((building) => Vec2.distance(building.position, position) >= radius);
  }
  begin(type: BuildingType, position: Vec2): PlacedBuilding | null {
    const recipe = this.recipes[type];
    // 关键：先校验位置和资源，再创建建筑，保证建造失败不会扣费。
    if (!recipe || !this.canPlace(position) || !this.state.spend(recipe.cost)) return null;
    const building: PlacedBuilding = { id: `${type}_${this.buildings.length + 1}`, recipe, position: position.clone(), durability: new Durability(100), progress: 0, built: false };
    this.buildings.push(building); this.events.emit('construction-started', building); return building;
  }
  update(dt: number): void {
    for (const building of this.buildings) if (!building.built && !building.durability.destroyed) {
      building.progress = Math.min(1, building.progress + dt / Math.max(0.1, building.recipe.buildTime));
      if (building.progress >= 1) { building.built = true; this.events.emit('construction-finished', building); }
    }
  }
}
