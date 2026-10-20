// Survival/StealSystem：资源偷取、容量回滚和观察者发现判定。
import { EventTarget, Vec2 } from 'cc';
import { GameState, ResourceType } from '../Core/GameState';

export interface Observer { position: Vec2; forward?: Vec2; }
export class StealSystem {
  readonly events = new EventTarget();
  constructor(public detectionRadius = 150, public viewDotThreshold = 0.35) {}
  steal(source: GameState, destination: GameState, type: ResourceType, amount: number, thief?: Observer, observers: Observer[] = []): number {
    const removed = source.remove(type, amount); const accepted = destination.add(type, removed);
    if (accepted < removed) source.add(type, removed - accepted);
    if (!accepted) { this.events.emit('failed', 'No resource or destination full'); return 0; }
    this.events.emit('stolen', type, accepted);
    if (thief && observers.some((observer) => this.wouldBeDetected(thief, observer))) this.events.emit('alarm', thief);
    return accepted;
  }
  wouldBeDetected(thief: Observer, observer: Observer): boolean {
    const direction = thief.position.clone().subtract(observer.position); const distance = direction.length();
    if (distance > this.detectionRadius) return false;
    if (!observer.forward) return true;
    direction.normalize(); return observer.forward.dot(direction) >= this.viewDotThreshold;
  }
}
