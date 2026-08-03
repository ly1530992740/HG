# 3D 战术 AI 模块流程

## 总体数据流

```mermaid
flowchart LR
    P["士兵感知组件"] --> B["小队信念状态"]
    B --> S["决策快照"]
    S --> I["战场影响图"]
    S --> U["Utility / TacticalOption"]
    I --> U
    U --> C["方案编译器"]
    C --> Q["任务调度器"]
    Q --> D["指令分发器"]
    D --> H["单兵 State Chart"]
    I --> R["最低代价路线规划"]
    R --> H
    H --> E["移动 / 掩体 / 武器 / 建筑执行器"]
    E --> Q
```

## 职责边界

| 模块 | 负责 | 不负责 |
| --- | --- | --- |
| 感知与信念 | 可见、声音、延迟报告、置信度和过期 | 直接选择战术 |
| 影响图 | 敌方火力叠加、压制、暴露、掩体、友军支援 | 发布士兵命令 |
| Utility / TacticalOption | 比较直接进攻、包抄、防守等完整方案 | 单兵逐帧移动 |
| 方案编译器 | 将方案拆为有依赖关系的任务 | 动画和射击时序 |
| Scheduler / Dispatcher | 任务生命周期、成员分配、生成 `SquadDirective3D` | 改写单兵安全规则 |
| 单兵 State Chart | 执行命令、生存打断、恢复命令、空闲警戒 | 改变全队战术目标 |
| 路线规划器 | 距离、峰值威胁、累计威胁、暴露时间和物理可达性 | 决定是否发动进攻 |

## 一次决策到执行

```mermaid
sequenceDiagram
    participant P as 感知/信念
    participant U as Utility/TacticalOption
    participant S as Scheduler
    participant D as Dispatcher
    participant H as SoldierStateChart3D
    participant R as RoutePlanner
    participant E as 执行器

    P->>U: 敌军兵力、火力覆盖、掩体与任务状态
    U->>U: 为直接进攻、包抄、防守分别打分
    U->>S: 提交得分最高的完整方案和任务图
    S->>D: 激活已满足前置条件的任务
    D->>H: 下发带版本号的 SquadDirective3D
    H->>R: 请求当前影响图上的最低代价路线
    R-->>H: 路点、总代价、峰值威胁、暴露时间
    H->>E: 移动、进掩体、瞄准、射击或操作建筑
    alt 遭遇压制或高危火力
        H->>H: 进入 SURVIVAL_OVERRIDE 并保存指令状态
        H->>R: 规划紧急掩体或最低风险撤离路线
        H->>E: 隐蔽、卧倒、短促还击
        H->>H: 危险下降后恢复原指令
    end
    E-->>H: 动作成功或失败
    H-->>S: directive_completed
```

## 单兵 State Chart

```mermaid
stateDiagram-v2
    [*] --> IDLE_SECURITY
    IDLE_SECURITY --> EXECUTE_ORDER: 收到新指令
    EXECUTE_ORDER --> SURVIVAL_OVERRIDE: 被压制或路线危险
    IDLE_SECURITY --> SURVIVAL_OVERRIDE: 空闲时遭遇危险
    SURVIVAL_OVERRIDE --> EXECUTE_ORDER: 危险下降且仍有指令
    SURVIVAL_OVERRIDE --> IDLE_SECURITY: 危险下降且无指令
    EXECUTE_ORDER --> IDLE_SECURITY: 指令完成
    EXECUTE_ORDER --> DEAD: 死亡
    SURVIVAL_OVERRIDE --> DEAD: 死亡
    IDLE_SECURITY --> DEAD: 死亡
```

`EXECUTE_ORDER` 内部按指令类型进入移动、占领掩体、攻击、压制、包抄、
侦察、固守、撤退或使用建筑。攻击由锁定目标、接敌、装填、瞄准、射击
组成；这些是明确转换，不再进行动作图搜索。

## 路线代价

路线不是单纯最短路。每条边的代价由移动距离加风险组成：敌军火力、压制
和暴露增加代价，掩体、隐蔽和友军支援降低代价；计划同时记录峰值威胁和
预计暴露时间。影响图版本变化且旧路线明显恶化时，单兵重新规划剩余路线。

## 失败与修复

任务有显式成功、失败和超时条件。`PLAN_REPAIR` 优先尝试换成员、换掩体、
换路线；只有修复无效或战场态势发生实质变化时，才重新选择整个战术方案。
单兵的生存打断不等同于任务失败，也不会错误发送完成信号。
