# 柳风界面

柳风是一款以菜单栏为入口的原生 macOS 工具。首要任务是查看温度和调节风扇；擦拭模式、更新和设置各保留一个明确入口。

使用 AppKit 与系统字体，正文 13 pt，次要信息 11 pt，数值使用等宽数字。浅色底色 #F5F6F4、内容底色 #FFFFFF、分隔 #E0E4E0、柳绿 #357A50、主文字采用系统 labelColor；深色随系统切换。布局使用 4、8、12、16、20 pt 间距。文字左对齐，状态和数值右对齐。

菜单栏标志是一片斜向上舒展的柳叶，18 pt 单色模板图像，保留叶脉负形。绿色只用于已选曲线和正在运行的状态。菜单不使用嵌套卡片；设置和更新按用途分组。关于信息收进系统应用菜单和设置底部。

菜单顺序：温度与风扇 → 调节开关与曲线 → 风扇面板、擦拭模式 → 设置、检查更新 → 退出。技术字段、采样周期、内部恢复机制留在文档或提示中，不放在日常操作路径上。

文案规则：一个事实只出现一次；动作使用短而明确的动宾词；正常状态不附加解释；权限或失败时才显示原因与恢复动作。保留擦拭模式的退出组合键与自动退出时间，因为它们影响使用。

设计参考与使用的 prompt：

- [Anthropic frontend-design](https://github.com/anthropics/skills/blob/main/skills/frontend-design/SKILL.md)：为主题选择一个识别点，控制其余视觉元素。
- [Impeccable distill](https://github.com/pbakaus/impeccable/blob/main/.agents/skills/impeccable/reference/distill.md)：移除重复信息、无作用的容器与解释；保留必要功能。
- [Impeccable clarify](https://github.com/pbakaus/impeccable/blob/main/.agents/skills/impeccable/reference/clarify.md)：让动作、结果、权限和恢复路径一眼可懂。
- [Apple 菜单指南](https://developer.apple.com/design/human-interface-guidelines/menus)：按用途分组并遵循系统菜单习惯。

本次设计 prompt：以一片柳叶为品牌识别点，重新组织原生 macOS 风扇工具的菜单。优先保证当前温度、风扇调节、擦拭模式和更新容易找到。删去无法改变用户决策的文案；不要增加营销口号、技术说明或装饰性分组。
