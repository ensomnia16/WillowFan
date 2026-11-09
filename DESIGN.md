# 柳风界面

柳风是一款以菜单栏为入口的原生 macOS 工具。首要任务是查看温度和调节风扇；擦拭模式、更新和设置各保留一个明确入口。

界面采用 AppKit 和系统字体，数值使用等宽数字。概览上方集中显示最高温度与两路风扇读数，当前控制状态放在标题旁。下方左列是调节开关、曲线和温度基准，右列是传感器温度。浅色采用雾绿背景，深色采用墨绿背景；温度主卡使用深柳绿底和回叶暗纹。

沿用用户确认的 A「回叶」。`Assets/WillowFan.icon` 把两片叶子保留为独立的矢量层，使用深柳绿底、浅白绿和薄荷绿前景。菜单栏用 18 pt 宽的完整双叶单色模板；悬停可看到控制状态和曲线名称。菜单顺序为读数、调节、风扇面板、擦拭模式、设置、更新、退出。设置分为启动与刷新、更新、权限。

Xcode 工程运行独立的设计预览。示例温度、转速及进程只用于预览；发布应用仍使用既有风扇引擎与服务。正常发布继续沿用 `Scripts/build.sh`。

文案规则：一个事实只出现一次；动作使用短而明确的动宾词；正常状态不附加解释；权限或失败时才显示原因与恢复动作。保留擦拭模式的退出组合键与自动退出时间，因为它们影响使用。

设计参考与使用的 prompt：

- [Anthropic frontend-design](https://github.com/anthropics/skills/blob/main/skills/frontend-design/SKILL.md)：为主题选择一个识别点，控制其余视觉元素。
- [Impeccable distill](https://github.com/pbakaus/impeccable/blob/main/.agents/skills/impeccable/reference/distill.md)：移除重复信息、无作用的容器与解释；保留必要功能。
- [Impeccable clarify](https://github.com/pbakaus/impeccable/blob/main/.agents/skills/impeccable/reference/clarify.md)：让动作、结果、权限和恢复路径一眼可懂。
- [Apple 菜单指南](https://developer.apple.com/design/human-interface-guidelines/menus)：按用途分组并遵循系统菜单习惯。

本次设计 prompt：以一片柳叶为品牌识别点，重新组织原生 macOS 风扇工具的菜单。优先保证当前温度、风扇调节、擦拭模式和更新容易找到。删去无法改变用户决策的文案；不要增加营销口号、技术说明或装饰性分组。

标志设计参考：[logo-design skill](https://github.com/kaankiziltug/logo-design-skill/blob/main/skills/logo-design/SKILL.md)。用户于本轮审核选择原版 A「回叶」，后续交付以该形态为准。
