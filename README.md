# 盈亏一眼 · YinKui（ProfitLook）

一个纯原生 UIKit / Swift 写的 iOS 基金持仓查看工具。无第三方依赖、无 CocoaPods / SPM，
Xcode 打开工程即可编译运行。App 数据全部保存在本机，无账号体系、无数据上传。

> 本仓库只存放**当前生效的 App 完整源码**。构建脚手架、历史产物与迭代过程中的旧实现不在此仓库。

## 功能

- **持仓管理**：添加 / 编辑 / 侧滑删除基金，支持手填市值，也支持填「持有份额」后
  按「份额 × 最新净值」自动重算市值（未填份额的基金维持手填值，向后兼容旧数据）。
- **净值刷新**：手动下拉刷新 + 可配置间隔的自动刷新；净值日 ≠ 今天时，界面如实标注
  「净值日收益」而非谎称今日。
- **总览头卡**：总市值、今日 / 累计收益切换（口径持久化）、带参考点的一句话洞察
  （如「3 只中 2 只上涨」）、一键隐藏金额（跨启动记忆）、滚动时收成与列表同宽同圆角的
  吸顶小计；隐私态下金额统一打码，百分比保留。
- **详情页**：单只基金明细与重仓股持仓。
- **设置**：自动刷新间隔、收益口径、涨红跌绿 / 绿涨红跌配色方案、清空数据。
- **本地基金代码库**：内嵌 28330 条「基金代码 → 名称」映射，输入代码即可离线查名，零网络。
- **系统适配**：深浅色外观、Dynamic Type、Reduce Motion、增强对比（Increase Contrast）、
  无障碍标签；金额使用等宽数字，刷新时不跳动。

## 目录结构

```
ProfitLook/
├── ProfitLook.xcodeproj/          Xcode 工程（project.pbxproj + shared scheme）
└── ProfitLook/
    ├── AppDelegate.swift          启动入口、Tab 容器
    ├── Fund.swift                 模型、持久化、格式化、设计令牌与通用 UI 组件
    ├── FundDB.swift               基金代码本地查表
    ├── HoldingsService.swift      公开净值 / 持仓数据抓取与解析
    ├── FundListVC.swift           主页列表、头卡、吸顶小计、刷新逻辑
    ├── FundDetailVC.swift         基金详情与重仓股
    ├── AddFundVC.swift            添加基金表单
    ├── EditFundVC.swift           编辑基金表单
    ├── SettingsVC.swift           设置页与刷新间隔选择器
    ├── Info.plist
    ├── funddb.txt                 基金代码全量库（Bundle 资源）
    └── Assets.xcassets/           App 图标（浅色 / 深色双外观）
```

## 构建

- Xcode 打开 `ProfitLook/ProfitLook.xcodeproj`，选择目标设备直接 Run。
- 目标系统 iOS 16 及以上（自定义 sheet detent 等 API）；真机在更高版本系统验证。
- 无签名 IPA 可通过 TrollStore 安装；本仓库不含任何二进制产物。
- 工程不需要额外依赖，也不需要任何密钥。

## 设计约束

圆角、卡片角色与文字层级统一由 `Fund.swift` 中的设计令牌管理：

| 令牌 | 作用 |
|---|---|
| `AppCardRadius` | 全 App 容器卡统一圆角 |
| `CardRole` | 卡片语义角色的排版尺度与间距 |
| `TextTier` | 次级文字四上下文（默认 / 增强对比 × 浅色 / 深色），均达 WCAG AA |
| `Theme` | 涨跌方向色，保持系统语义色，随外观自动切换 |

内容层使用系统实色与标准材质，不使用自定义玻璃光效或厚重阴影。
