# Release 流程

## 一、目标产物

发布产物为 macOS App 压缩包：

- `ClaudeAgentConnector-macOS-Release.zip`
- `ClaudeAgentConnector-macOS-Release.zip.sha256`

## 二、本地构建

前提：macOS + Xcode + XcodeGen。

```bash
brew install xcodegen
make release
```

脚本执行逻辑：

1. `xcodegen generate --spec project.yml`
2. `xcodebuild ... -configuration Release`
3. 使用 `ditto` 打包 `.app` 为 zip
4. 生成 SHA256 校验文件

## 三、CI 验证

`ci-macos.yml` 在以下场景自动运行：

- PR
- push 到 `main` 与 `cursor/**`

它会生成工程并执行 Debug 构建，确保主干可编译。

## 四、正式发布

1. 创建并推送语义化 tag（例如 `v0.1.0`）：

   ```bash
   git tag v0.1.0
   git push origin v0.1.0
   ```

2. `release.yml` 会自动：
   - 构建 Release app
   - 上传构建产物到 workflow artifact
   - 将 zip 与 sha256 附件发布到 GitHub Release

## 五、版本号管理

在 `project.yml` 中维护：

- `MARKETING_VERSION`：展示版本（如 0.1.0）
- `CURRENT_PROJECT_VERSION`：构建号（递增整数）
