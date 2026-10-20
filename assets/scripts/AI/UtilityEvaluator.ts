// AI/UtilityEvaluator：根据敌情和士气选择当前最有价值的战术。
import { BeliefSnapshot } from './BeliefState';
import { DirectiveType } from './Directives';
export class UtilityEvaluator {
  choose(snapshot: BeliefSnapshot, morale = 1): DirectiveType { if (!snapshot.hostileCount) return 'guard'; if (morale < 0.25) return 'withdraw'; if (snapshot.hostileCount >= 3) return 'suppress'; return snapshot.confidence > 0.65 ? 'attack' : 'recon'; }
  score(type: DirectiveType, snapshot: BeliefSnapshot, morale = 1): number { const base: Record<DirectiveType, number> = { move: 0.2, guard: 0.35, attack: 0.65, suppress: 0.7, flank: 0.6, recon: 0.45, withdraw: 1 - morale, 'take-cover': 0.55 }; return base[type] + snapshot.hostileCount * (type === 'suppress' ? 0.08 : 0.02); }
}
