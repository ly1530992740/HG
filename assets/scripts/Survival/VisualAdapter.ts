// Survival/VisualAdapter：把战斗逻辑的阵营和姿态转换成视觉层可消费的数据。
export type Faction = 'ally' | 'enemy' | 'villager' | 'medic';
export type Pose = 'idle' | 'walk' | 'aim' | 'fire' | 'reload' | 'death' | 'work';
/** Data-only replacement for the Godot Holstin visual adapter. Cocos models/sprites can consume this state. */
export class CharacterVisualAdapter { faction: Faction = 'ally'; pose: Pose = 'idle'; frame = 0; configure(faction: Faction): void { this.faction = faction; } updatePose(pose: Pose, frame: number): void { this.pose = pose; this.frame = frame; } }
