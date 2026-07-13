# Pwdlock 三端完整流程 Figma 原型实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在一个新的 Figma Design 文件中交付 macOS、Windows、Android 的完整 Pwdlock 密码库流程原型。

**Architecture:** 建立一套本地 Figma 基础变量与可复用组件，再分别组织 macOS、Windows、Android 页面。三端共享内容、文案、状态规则和视觉令牌；桌面采用三栏工作区，Android 采用底部导航和全屏任务流。

**Tech Stack:** Figma Design、Figma Plugin API、SF Pro 字体、Figma 原型链接。

---

## 文件与页面结构

- 创建 Figma 文件 `Pwdlock · 三端完整原型`：独立设计文件。
- 创建 `00 · Foundations`：本地色彩变量、间距/圆角说明、文字层级和视觉规则。
- 创建 `01 · macOS`：桌面完整流程页面。
- 创建 `02 · Windows`：Windows 完整流程页面。
- 创建 `03 · Android`：移动端完整流程页面。
- 创建 `04 · Components`：按钮、输入、导航、条目行、标签、提示、弹窗与冲突比较模块。

### Task 1: 创建 Figma 文件与页面骨架

**Files:**
- Create: Figma Design 文件 `Pwdlock · 三端完整原型`

- [ ] **Step 1: 创建空白 Design 文件**

调用 `create_new_file`，名称为 `Pwdlock · 三端完整原型`，编辑器为 `design`。

- [ ] **Step 2: 创建五个页面**

调用 `use_figma` 创建并命名 `00 · Foundations`、`01 · macOS`、`02 · Windows`、`03 · Android`、`04 · Components`；切换页面时使用 `await figma.setCurrentPageAsync(page)`。

- [ ] **Step 3: 验证页面结构**

调用元数据读取，确认所有五个页面存在且命名准确。

### Task 2: 建立明亮克制的视觉基础与组件

**Files:**
- Modify: `00 · Foundations`
- Modify: `04 · Components`

- [ ] **Step 1: 创建颜色与尺寸变量**

创建局部变量：`Color/Background=#F5F5F7`、`Color/Surface=#FFFFFF`、`Color/Text Primary=#1D1D1F`、`Color/Text Secondary=#6E6E73`、`Color/Border=#E5E5EA`、`Color/Accent=#0071E3`、`Color/Danger=#FF3B30`。每个变量设置对应 scopes：表面色为 `FRAME_FILL`/`SHAPE_FILL`，文字色为 `TEXT_FILL`。

- [ ] **Step 2: 创建文字层级**

加载可用的 SF Pro 字体后，建立并标注 Display 32、Heading 24、Section 17、Body 15、Caption 13。文字使用主要或次要文字变量，不引入额外品牌色。

- [ ] **Step 3: 创建基础组件**

创建组件：主/次要/危险按钮、文本输入、搜索框、侧栏导航项、底部导航项、密码条目行、状态标记、Toast、确认弹窗。重复元素必须以实例使用。

- [ ] **Step 4: 截图检查基础页**

调用 `get_screenshot`，检查文字未裁切、白底与灰边界可辨、强调蓝只用于关键操作与选中状态。

### Task 3: 设计 macOS 完整流程

**Files:**
- Modify: `01 · macOS`

- [ ] **Step 1: 创建安全入口**

建立首次设置主密码、解锁、锁定遮罩三帧。首次设置必须显示“主密码遗失后无法恢复”，解锁失败统一显示“密码错误或文件损坏”。

- [ ] **Step 2: 创建三栏密码库与条目流程**

建立侧栏、可搜索列表、详情面板，加入分类、弱密码/重复密码、冲突计数、密码遮蔽、字段复制、编辑和删除确认。复制后显示 30 秒清除 Toast。

- [ ] **Step 3: 创建生成器与备份流程**

建立生成器、导出说明、独立导出密码、导出完成、导入预检、导入密码和结果摘要。导入预检只展示格式版本及文件大小。

- [ ] **Step 4: 创建冲突中心与设置**

建立冲突中心、字段差异比较、明确保留本地/导入、删除/恢复裁决、处理完成摘要；建立自动锁定、生物识别、剪贴板、主密码和隐私设置。

- [ ] **Step 5: 添加原型链接并截图检查**

从解锁串联至密码库、编辑、导出、导入、冲突处理和设置。对每一帧调用截图检查，确认无敏感内容出现在认证前。

### Task 4: 设计 Windows 完整流程

**Files:**
- Modify: `02 · Windows`

- [ ] **Step 1: 创建 Windows 安全入口与主工作区**

沿用 macOS 语义和文案，使用更紧凑的行高、明确的顶端命令栏和 Windows 友好的窗口栏。

- [ ] **Step 2: 复用组件完成条目、生成器、导入导出和冲突流程**

以组件实例实现与 macOS 相同状态：遮蔽密码、复制倒计时、认证前数据隐藏、导入摘要和明确冲突裁决。

- [ ] **Step 3: 添加链接与视觉检查**

串联主要路径；截图确认命令栏、列表密度和详情栏无重叠或裁切。

### Task 5: 设计 Android 完整流程

**Files:**
- Modify: `03 · Android`

- [ ] **Step 1: 创建移动安全入口与底部导航**

建立欢迎/设置主密码、解锁、锁定、密码库、生成器、设置。密码库配搜索、横向分类筛选及悬浮新增按钮。

- [ ] **Step 2: 创建全屏条目任务流**

建立详情、编辑、新建、复制提示和删除确认。详情密码默认遮蔽，显示与复制均为局部显式动作。

- [ ] **Step 3: 创建移动备份、导入与冲突任务流**

建立导出密码、导出完成、导入预检、导入密码、导入摘要、冲突列表和裁决。认证前仍只显示版本和大小。

- [ ] **Step 4: 添加原型链接与截图检查**

用点击区域串联底部导航、条目操作和导入/冲突路径；截图检查手机安全区、底部导航和浮动按钮无相互遮挡。

### Task 6: 全局验证与交付

**Files:**
- Modify: 全部 Figma 页面

- [ ] **Step 1: 执行流程走查**

逐端验证：锁定 → 解锁 → 查看条目 → 编辑 → 复制 → 导出 → 导入 → 摘要 → 冲突裁决 → 设置。

- [ ] **Step 2: 执行安全文案走查**

检查每端的认证前隐藏、统一失败错误、主密码不可恢复提示、独立导出密码提醒和冲突不静默覆盖规则。

- [ ] **Step 3: 交付 Figma 文件链接**

输出 Figma 文件 URL，并说明包含的页面与完整流程范围。
