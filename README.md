# Docker VPS Deploy Template

一套面向个人项目的 GitHub Actions → 单台 Linux VPS 自动部署模板。适用于 FastAPI、Node.js、React、静态网站及其他能够用 Docker Compose 运行的项目。

## 能力

- 推送 `main` 后自动测试和发布
- 使用项目独立的 SSH 部署密钥
- 每个 Git commit 对应一个服务器 release 目录和镜像标签
- 公网 HTTPS 健康检查
- 候选版本失败时重新启动上一个成功版本
- Docker Compose 数据卷保持数据库数据
- PostgreSQL 压缩备份与过期清理脚本
- 支持多个项目共用一台 VPS

> 数据库迁移仍应保持向后兼容。自动回滚应用镜像不能自动逆转破坏性的数据库迁移。

## 服务器目录约定

```text
/home/deploy/apps/<app-name>/
├── current -> releases/<successful-sha>
├── releases/
│   ├── <commit-sha>/
│   └── ...
├── shared/
│   └── app.env
└── uploads/
```

## 1. 初始化服务器（只执行一次）

在本机为某个项目生成独立密钥：

```bash
ssh-keygen -t ed25519 -C "github-actions-my-app" -f ./my-app-deploy-key
```

把 `my-app-deploy-key.pub` 的内容作为 `DEPLOY_PUBLIC_KEY`，在 Ubuntu 服务器执行：

```bash
sudo DEPLOY_PUBLIC_KEY='ssh-ed25519 AAAA...' bash scripts/bootstrap-server.sh
```

脚本会安装 Docker、创建 `deploy` 用户、配置 2 GB swap，并开放 22、80、443 端口。

注意：Docker 组本质上具有主机管理员级能力。高安全场景应改用独立主机、rootless Docker 或受限部署服务。

## 2. 配置业务仓库 Secrets

在每个业务仓库的 `Settings → Secrets and variables → Actions` 添加：

| Secret | 内容 |
|---|---|
| `DEPLOY_HOST` | 服务器公网 IP |
| `DEPLOY_USER` | `deploy` |
| `DEPLOY_SSH_KEY` | 项目部署私钥全文 |
| `DEPLOY_KNOWN_HOSTS` | 推荐：服务器 SSH host key |
| `APP_ENV` | 项目生产环境变量，多行 `.env` 格式 |

获取并人工核对服务器 host key 后保存：

```bash
ssh-keyscan -H YOUR_SERVER_IP
```

`APP_ENV` 示例：

```dotenv
POSTGRES_USER=app
POSTGRES_PASSWORD=replace-with-random-value
POSTGRES_DB=app
JWT_SECRET=replace-with-random-value
```

GitHub 保存 Secret 后不会再次显示原文。

## 3. 在业务仓库调用模板

复制 [`examples/fastapi-react/caller-workflow.yml`](examples/fastapi-react/caller-workflow.yml) 到业务仓库：

```text
.github/workflows/deploy.yml
```

最小调用：

```yaml
jobs:
  deploy:
    uses: naruto-823/docker-vps-deploy-template/.github/workflows/reusable-deploy.yml@v1
    with:
      app_name: my-app
      compose_file: compose.production.yml
      health_url: https://api.example.com/api/health
    secrets: inherit
```

生产项目应固定到发布标签（如 `@v1`）或完整 commit SHA，不建议引用浮动分支。

## Compose 要求

业务项目需要提供生产 Compose 文件，并遵循：

1. 自建服务同时声明 `build` 和带版本变量的 `image`：

   ```yaml
   api:
     image: my-app-api:${IMAGE_TAG}
     build: ./backend
   ```

2. 数据库必须使用 named volume。
3. 服务使用 `restart: unless-stopped`。
4. Caddy 或其他网关监听 80/443。
5. `health_url` 必须是公网 HTTPS 2xx 接口。
6. `.env`、私钥、数据库文件不得提交到 Git。

完整示例位于 [`examples/fastapi-react`](examples/fastapi-react)。

## 发布过程

```text
checkout → project checks → package source → SSH upload
         → build commit-tagged images → start candidate
         → public health check → promote current symlink
                              ↘ failure: restart previous release
```

同一个 `app_name` 使用 GitHub concurrency lock，不会并行修改同一套生产服务。

## 手动发布

调用仓库的 Workflow 带有 `workflow_dispatch` 后，可在 GitHub Actions 页面点击 `Run workflow`。

## PostgreSQL 备份

在服务器执行：

```bash
POSTGRES_USER=app POSTGRES_DB=app \
  scripts/backup-postgres.sh /home/deploy/apps/my-app
```

默认保留 14 天。建议通过 cron 每天执行，并把备份同步到独立对象存储。必须定期演练恢复流程，不能只验证备份文件存在。

## 发布版本

- `v1`：单 VPS、Docker Compose、SSH 发布、健康检查与应用级回滚。
- 后续破坏性修改发布 `v2`；兼容修复更新 `v1` 标签并同时发布不可变的 `v1.x.x` 标签。

## 安全建议

- 每个项目使用不同的部署密钥。
- 保护业务仓库 `main` 分支。
- 限制拥有仓库写权限的成员。
- 定期轮换 SSH 密钥和应用 Secrets。
- 优先设置 `DEPLOY_KNOWN_HOSTS`，避免首次连接依赖未经核对的 `ssh-keyscan`。
- 为 GitHub Actions 固定第三方 Action 的 commit SHA；示例只使用 GitHub 官方 Action。
- 不允许来自不可信 PR 的代码访问生产 Secrets。
