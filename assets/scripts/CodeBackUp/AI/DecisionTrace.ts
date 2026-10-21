// AI/DecisionTrace：保存最近的战术选择，供调试面板显示。
export interface DecisionTraceEntry { at: number; choice: string; score: number; reason: string; }
export class DecisionTrace { readonly entries: DecisionTraceEntry[] = []; record(choice: string, score: number, reason: string): void { this.entries.push({ at: Date.now(), choice, score, reason }); if (this.entries.length > 50) this.entries.shift(); } latest(): DecisionTraceEntry | null { return this.entries[this.entries.length - 1] || null; } }
