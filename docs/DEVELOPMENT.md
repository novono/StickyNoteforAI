# 开发说明

## 构建

`./build.sh` 递归收集 `Sources/` 下的 Swift 源码，以 Swift 5 语言模式编译，目标为 `arm64-apple-macosx14.0`。只依赖系统的 AppKit、QuartzCore、UniformTypeIdentifiers 等框架。

应用输出到 `build/PaperMemory.app`，包含 `Info.plist`、可执行文件和 `Resources/`，随后进行 ad-hoc 签名。`build/` 已从版本控制中排除。`Info.plist` 与 `Sources/Domain/Note.swift` 中的版本号应一起更新。

为了兼容现有安装，应用的内部名称、bundle identifier 和默认数据目录保持 PaperMemory 身份；仓库名为 StickyNoteforAI，显示名称为“贴贴”。

## 验证

```sh
./build.sh
./verify.sh
```

也可对指定的构建运行 `./verify.sh /absolute/path/PaperMemory.app`。验证脚本会使用当前源码编译原生测试，并对指定应用运行 CLI/MCP 集成与签名检查，因此应先用当前源码构建该应用。

| 测试 | 覆盖范围 |
| --- | --- |
| `Tests/test_integration.py` | CLI/MCP、字段限制、并发事务、批量归类原子性、冲突与损坏文件保护 |
| `Tests/test-motion.swift` | 贴撕动画完成、中断、编辑器与位置恢复 |
| `Tests/test-rich-text.swift` | 中英文、排版、删除线、图片的保存和读取 |
| `Tests/test-window-state.swift` | 桌面层级、置顶解锁、显示隐藏、同窗展开收起、同步与草稿合并 |
| `Tests/test-inertia.swift` | 释放速度、指数减速、多屏边界、抓停、位置保存与中断 |
| `Tests/test-paper-age.swift` | 纸龄曲线、上限、稳定纹理、正文区域保护、四种纸色对比度 |

原生测试需要当前用户有图形桌面会话；不要把完整套件当作纯无界面的 Linux / SSH 测试。窗口状态与惯性集成测试使用真实 AppKit 窗口，并注入可控制完成时机的尺寸过渡，以稳定验证草稿保存、收起和删除后的晚到回调。贴撕动画与拖动仍执行生产动画代码；实际展开动画的视觉效果另在运行的应用中检查。

每次运行的数据、可执行文件与纸龄预览放在 `build/check.*`，不触碰日常便签。CLI/MCP 测试使用系统临时目录，完成后自行清理。测试与字体脚本所用 Python 为 Python 3；除重建字体外，测试无额外 Python 包依赖。

## 视觉检查

`test-paper-age.swift` 会生成 `paper-age/paper-aging.png` 和 `paper-age/fresh-paper.png`，适合检查纸龄在不同颜色上的变化。

运行贴撕动画与随机纸角预览（zsh）：

```sh
mkdir -p build
sources=(Sources/**/*.swift)
sources=("${(@)sources:#Sources/main.swift}")
xcrun swiftc -swift-version 5 \
  -framework AppKit -framework QuartzCore -framework UniformTypeIdentifiers \
  "${sources[@]}" scripts/render-motion.swift -o build/render-motion
build/render-motion Resources build/motion-preview
```

预览调用生产绘制代码，示例文字与真实便签数据无关。检查时也应在应用中确认文字选择、图片编辑、展开收起和桌面切换的实际行为。

## 字体与图标

日常构建直接使用仓库内的字体，不运行字体生成程序。需要调整笔画时，再创建单独的 Python 环境：

```sh
python3 -m venv .venv
.venv/bin/pip install -r scripts/requirements-fonts.txt
.venv/bin/python scripts/make-light-fonts.py
xcrun swift scripts/verify-fonts.swift Resources
```

脚本读取 `Resources/` 中的原始字体，生成经过改名的六套 Light 衍生字体。字体的版权和 OFL 授权必须保留；更改算法后应重新检查中文缺字、小字号可读性与英文搭配。

图标重建：

```sh
mkdir -p build
xcrun swift scripts/make-icon.swift Resources/AppIcon.png build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
```

`Resources/AppIcon.png` 是已经确定的透明图标母版；脚本只缩放并打包，不重新绘制图案。设计说明与生成提示词见 [图标设计](ICON-DESIGN.md)。

## 提交约定

- 源码、测试、资源与文档进入版本控制；应用包、临时数据、生成的测试程序和 Python 虚拟环境不提交。
- 数据写入通过 `Store` 的事务与 `NoteDocuments`，避免绕过修订号检查。
- 新的 AI 命令在 `NoteService` 实现，MCP 负责协议适配；变更时同步工具 schema、文档和集成验证。
- 调整窗口或动画时，保留同窗展开、草稿保存、删除中断与停稳后持久化约束，详见 [架构说明](ARCHITECTURE.md)。

## 发布安装包

```sh
./build.sh
./scripts/package-release.sh
```

输出到 `dist/`：`PaperMemory-macOS-arm64.dmg`、`PaperMemory-macOS-arm64.zip` 和 `SHA256SUMS`。DMG 含应用、指向 `/Applications` 的快捷方式和安装说明；ZIP 只含应用。打包脚本检查架构、版本与签名，验证 DMG 完整性，并从 ZIP 重新解压应用运行 CLI/MCP 集成测试。打包需要 macOS 自带的 `hdiutil`、`ditto` 和 Python 3。

正式发布前，在有图形桌面的 Mac 上运行完整 `./verify.sh` 并检查实际界面。更新版本号、`CHANGELOG.md`，新增 `docs/releases/v<版本>.md`；提交后推送对应标签，例如 `v1.3.1`。`.github/workflows/release.yml` 会在 GitHub 的 `macos-15` 托管环境构建、打包、验证，并先上传到草稿，成功后公开 Release。只使用当前仓库的临时 `GITHUB_TOKEN`，无需个人访问令牌。

发布资产采用固定文件名，使 README 的 `releases/latest/download/…` 链接随最新版本自动更新。已公开的版本不会被工作流覆盖；重试只可继续尚未公开的草稿。正式版本标签与应用版本必须一致，修改已发布内容时应增加新版本。

当前为 **ad-hoc 签名，未做 Developer ID 签名与 Apple 公证**。代码签名完整性检查通过不等于通过 Gatekeeper 或 Apple 公证；README、安装说明与 Release 必须如实保留这一状态。
