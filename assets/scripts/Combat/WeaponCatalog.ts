// Combat/WeaponCatalog：对武器定义提供查询和列表接口。
import { WeaponDefinition, WEAPONS } from './WeaponFireCycle';
export class WeaponCatalog { get(id: string): WeaponDefinition { return WEAPONS[id] || WEAPONS.rifle; } list(): WeaponDefinition[] { return Object.keys(WEAPONS).map((id) => WEAPONS[id]); } }
