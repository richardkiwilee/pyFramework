"""TheGreatConquest TUI 演示层。

基于可复用框架 pyconsole（双缓冲渲染 + 动作名按键 + 场景栈 + 模糊搜索百科），
业务逻辑层为 pydemo.game（纯逻辑，无 IO）。本包只做"表现层"：
把 pydemo.game 的动作接口映射成场景与按键交互，详见 操作逻辑.md。

框架与业务分离：pyconsole 保持不改、可复用；pydemo.game 保持不改；
所有游戏专属代码集中在本包。
"""
