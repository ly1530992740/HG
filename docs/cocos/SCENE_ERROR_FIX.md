# 场景启动报错修复记录

## 原因

旧场景使用了：

```json
"__type__": "cc.ScriptComponent"
```

`cc.ScriptComponent` 不是 Cocos Creator 3.8.8 中可以直接反序列化的组件类，因此 Creator 报：

```text
Missing class: cc.ScriptComponent
Script "cc.ScriptComponent" ... is missing or invalid
Open scene failed
```

修正脚本组件后，场景仍可能在激活时失败。Creator 3.8.8 的 `Scene._activate()` 会调用 `SceneGlobals.activate(scene)`，所以 `_globals` 不能为 `null`。此前手写场景还使用了非标准的 `active` 字段和空 Prefab 引用，导致 `SceneGlobals` 没有建立。

## 修复

场景脚本组件现在使用 Creator 编译器生成的类注册 ID，例如：

```json
"__type__": "c4000AAAABAAIAAAAAAAAEE"
```

这个 ID 对应 `AIPlayground.ts` 的 `@ccclass('AIPlayground')` 注册结果。其他场景也使用各自的 Creator 编译注册 ID。

每个场景也已按 Creator 3.8.8 的序列化结构重建：

- Scene 使用 `_active`，并把 `_globals` 指向有效的 `cc.SceneGlobals`。
- 补齐 `AmbientInfo`、`ShadowsInfo`、`SkyboxInfo`、`FogInfo`、`OctreeInfo`、`SkinInfo`。
- 清除手写场景中的无效空 PrefabInfo 引用。

已修复场景：

- `assets/scenes/Main.scene`
- `assets/scenes/playtest/PlayerPlayground.scene`
- `assets/scenes/playtest/CombatPlayground.scene`
- `assets/scenes/playtest/BuildPlayground.scene`
- `assets/scenes/playtest/AIPlayground.scene`
- `assets/scenes/tests/*.scene`

## 验证

- 10 个场景全部重新导入到 Cocos `library`，每个场景包含 `SceneGlobals` 及 6 个环境配置对象。
- 每个场景导入后的脚本组件类型都不是 `cc.ScriptComponent`。
- 组件类型与 Creator 预览编译模块中的 `_RF.push` 注册 ID 一致。
- 每个场景的 `Scene._globals` 都指向有效的 `cc.SceneGlobals` 记录。
- 最新资源库内容中没有旧的 `cc.ScriptComponent` 类型。

当前验证覆盖源文件结构和 Creator Asset Database 导入。尚未通过 Creator 原生编辑器确认打开后再点预览；如果 Console 仍显示错误，请先清空旧消息再复测，新的错误需要带时间戳才能与 `temp/logs/project.log` 对上。

如果编辑器仍显示旧的 Console 条目，点击 Console 的 `Clear` 后再打开场景；旧日志不会自动消失。
