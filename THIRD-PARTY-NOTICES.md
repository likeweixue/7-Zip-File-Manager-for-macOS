# 第三方许可声明 / Third-Party Notices

本项目（7-Zip File Manager for macOS）自身源码采用 MIT 许可证，见 [LICENSE](LICENSE)。
但它**内置并分发**了 7-Zip 官方命令行程序 `7zz`，该二进制文件仍受其原有许可证约束。

This project's own source code is MIT-licensed (see [LICENSE](LICENSE)). It
**bundles and redistributes** the official 7-Zip command-line binary `7zz`,
which remains under its own licenses.

---

## 1. 7-Zip / 7zz

| 项目 | 内容 |
|---|---|
| 组件 | `7zz`（macOS 通用二进制，x86_64 + arm64） |
| 版本 | 26.05 |
| 来源 | <https://github.com/ip7z/7zip> （7-Zip 官方源码仓库，发布物） |
| 发布页 | <https://github.com/ip7z/7zip/releases/tag/26.05> |
| 版权 | Copyright (C) 1999-2026 Igor Pavlov |
| 许可证 | **GNU LGPL 2.1 或更高版本**（主要部分）<br>GNU LGPL + **unRAR license restriction**（RAR 解压相关代码）<br>**BSD 3-clause**（LZFSE / ZSTD 解压代码）<br>**BSD 2-clause**（XXH64 代码） |

> 更正一个常见误解：7-Zip **不是 GPL**，而是 **LGPL**（Lesser GPL）。
> 差别在于 LGPL 允许以「独立程序 + 动态/进程调用」的方式与闭源软件组合分发，
> 只需保证 7-Zip 自身部分的开源义务。完整原文见
> [LICENSES/7-Zip-License.txt](LICENSES/7-Zip-License.txt)。

### 原许可证全文

- [LICENSES/7-Zip-License.txt](LICENSES/7-Zip-License.txt) —— 7-Zip 官方发布包中的 `License.txt` 原文（含 LGPL 声明、BSD 3-clause、BSD 2-clause、unRAR 限制）
- [LICENSES/LGPL-2.1.txt](LICENSES/LGPL-2.1.txt) —— GNU Lesser General Public License v2.1 全文

### 本项目的合规做法

7-Zip 的许可证原文明确要求：

> Redistributions in binary form must reproduce related license information
> from this file.

即**二进制分发时必须随附该许可证信息**。因此：

1. `7zz` 原样打包，**未做任何修改**（未打补丁、未重新编译、未 strip）。
2. 应用包内 `7-Zip File Manager.app/Contents/Resources/` 下随附了：
   - `7zip-License.txt` —— 7-Zip 官方许可证原文
   - `7zip-readme.txt` —— 7-Zip 官方 readme
   - `LGPL-2.1.txt` —— LGPL 2.1 全文
3. 应用内「帮助 → 关于」列出了 7-Zip 版权与许可证入口。
4. 本项目**不修改 7-Zip 源码**，因此不承担 LGPL 对衍生作品的重链接义务；
   7-Zip 与 GUI 之间是「独立进程调用」（mere aggregation），不是静态/动态链接。
5. 7-Zip 的**完整对应源码**可直接从上游获取：
   <https://github.com/ip7z/7zip> 或 <https://www.7-zip.org/download.html>
   （本项目构建脚本 `build.sh` 从上游 release 下载的 `src.7z` 同一版本即可对应）。

### unRAR 限制

RAR 解压引擎源自 unRAR 源码，版权归 Alexander Roshal 所有。限制条款：

> The unRAR sources cannot be used to re-create the RAR compression algorithm,
> which is proprietary. Distribution of modified unRAR sources in separate form
> or as a part of other software is permitted, provided that it is clearly
> stated in the documentation and source comments that the code may not be used
> to develop a RAR (WinRAR) compatible archiver.

**本项目不包含 unRAR 源码，也不实现 RAR 压缩**，仅通过 `7zz` 调用其解压能力，
不构成对该限制的违反。

---

## 2. 图标

`tools/make_icon.swift` 用 Core Graphics 程序化绘制（蓝色圆角底 + 白色文档卡片 + 黄色标题条 + `7z` 字样），
为原创设计，不包含 7-Zip 官方图标资源（官方图标为 Igor Pavlov 的商标/版权资产）。
`7-Zip` 名称仅用于指明所调用的压缩引擎，属于合理使用。

---

## 3. 运行时依赖

无。应用不依赖 Homebrew、p7zip、Xcode 运行时或任何第三方框架，
仅使用 macOS 系统自带的 SwiftUI / AppKit / Foundation。
