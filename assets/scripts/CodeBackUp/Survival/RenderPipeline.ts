// Survival/RenderPipeline：低分辨率、暗角、颗粒和调色的配置入口。
export interface RenderPipelineConfig { width: number; height: number; vignette: number; grain: number; palette: string; }
/** Cocos replacement for the Godot post-process entry point; actual material is configured in the editor. */
export class RenderPipelineConfigService {
  config: RenderPipelineConfig = { width: 320, height: 180, vignette: 0.35, grain: 0.08, palette: 'holstin-dark' };
  configure(values: Partial<RenderPipelineConfig>): RenderPipelineConfig { this.config = { ...this.config, ...values }; return this.config; }
}
