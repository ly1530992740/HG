// AI/QwenBrain：可选外部模型的安全适配器，非法输出统一回退 guard。
import { DirectiveType, SquadDirective, DirectiveFactory } from './Directives';
const ALLOWED: DirectiveType[] = ['move', 'guard', 'attack', 'suppress', 'flank', 'recon', 'withdraw', 'take-cover'];
/** Deterministic adapter point for an optional external LLM. Invalid output always falls back safely. */
export class QwenBrainAdapter {
  constructor(private factory = new DirectiveFactory()) {}
  parse(raw: unknown): SquadDirective { const type = typeof raw === 'object' && raw && 'directive' in raw ? String((raw as any).directive) as DirectiveType : 'guard'; return this.factory.make(ALLOWED.indexOf(type) >= 0 ? type : 'guard', undefined, undefined, 1); }
}
