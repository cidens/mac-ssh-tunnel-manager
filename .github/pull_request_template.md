## 关联 Issue

请填写 `Closes #<issue-number>` 或说明为什么本次改动不需要 Issue。

## 变更说明

请简要说明本 PR 解决的问题、主要实现和用户影响。

## 验证结果

请列出实际执行的测试命令和结果。

## 检查清单

- [ ] 已关联公开 Issue，或已经说明无需 Issue 的原因。
- [ ] 已运行 `swift test`。
- [ ] 已运行 `git diff --check`。
- [ ] 如果改动影响打包或资源，已运行 `./scripts/build-app-bundle.sh /private/tmp/SSH\ Tunnel\ Manager.app`。
- [ ] 没有提交真实 Host、内网 IP、公网 IP、用户名、私钥路径、token、密码或完整 SSH 配置。
- [ ] 如果新增用户可见文案，已同步更新英文和简体中文本地化资源。
- [ ] 如果改变用户行为、配置格式或发布内容，已更新对应文档和 `CHANGELOG`。

## 风险与后续工作

请说明安全、兼容、迁移或回退风险；没有时填写“无”。
