// Combat/Concealment：把隐蔽值转换成感知可用的可见度倍率。
export class ConcealmentComponent { value = 0; constructor(public max = 1) {} set(value: number): void { this.value = Math.max(0, Math.min(this.max, value)); } visibilityMultiplier(): number { return 1 - this.value * 0.65; } }
