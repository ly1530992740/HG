# 仓库说明

本仓库是 Cocos Creator 3.8.8 项目，仓库根目录是唯一的活动项目边界。Godot 已退役；归档的设计文档仅作为参考资料。

开始实现前，先阅读 [Cocos 项目 Skill](.agents/skills/cocos-project/SKILL.md) 及其中链接的相关参考文档。模块归属遵循 [MODULE_BOUNDARIES.md](docs/architecture/MODULE_BOUNDARIES.md)。

## 硬性边界

- 所有活动项目代码、场景、资源、测试、构建设置和项目文档必须位于本仓库内。
- 不得新增 Godot 脚本、场景、项目配置、编辑器缓存或 Godot 运行时依赖。
- `docs/design-archive/` 只读，内容属于历史设计输入。当前实现契约以 `docs/architecture/` 和本 Skill 为准。
- 不得编辑 Cocos 生成的缓存或构建产物：`library/`、`temp/`、`build/`、`profiles/`、`local/`、`native/`。
- 除非明确执行框架任务，不得修改 Cocos Creator 引擎版本、项目 UUID、场景序列化格式或依赖/构建工具链。
- Cocos 资源必须保留对应的 `.meta` 文件；移动或重命名资源时必须保留 UUID。

## 所有权

用户负责框架方向，并批准模块契约、公共 API、依赖方向、根装配、测试基础设施和构建配置的变更。Agent 在已约定的模块契约内实现业务/玩法需求。如果请求需要修改框架，先说明所需的最小契约变更；在等待或处理框架变更时，仍可继续完成不依赖该变更的业务工作。

## 完成证据

每次代码或场景变更都必须报告受影响的模块、已执行的验证、验证结果以及未执行的检查。没有执行的测试、预览或构建，绝不能描述为通过。所有变更和验证都必须限制在本仓库内。
