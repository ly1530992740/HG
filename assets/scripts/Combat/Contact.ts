// Combat/Contact：把观察者、敌人、位置和刺激来源封装成统一接触报告。
import { Vec2 } from 'cc';
import { Soldier } from './Soldier';
export interface ContactReport { observer: Soldier; hostile: Soldier; position: Vec2; confidence: number; stimulus: 'vision' | 'sound'; }
export class CombatContact { static report(observer: Soldier, hostile: Soldier, stimulus: 'vision' | 'sound' = 'vision'): ContactReport { const distance = Vec2.distance(observer.position2D, hostile.position2D); return { observer, hostile, position: hostile.position2D.clone(), confidence: Math.max(0, 1 - distance / observer.sightRange), stimulus }; } }
