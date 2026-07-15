# 自建镜像部署与更新指南（保留改动 + 跟随官方更新）

本指南针对**已修改源码**（如把 Claude OAuth 的 `client_id` 改为 `dae2cad8`，见
`backend/internal/pkg/oauth/oauth.go`）的场景：用 GitHub Actions 在云端构建镜像并推送到
GHCR，任何机器直接 `docker pull` 部署；更新时同步官方仓库并自动重建，你的改动始终保留。

```
你的 fork (带改动)  --push-->  GitHub Actions 云端构建  --push-->  ghcr.io/<你>/sub2api:latest
                                                                          |
   官方 Wei-Shaw/sub2api  --sync-upstream.sh 合并-->  你的 fork          | docker pull
                                                                          v
                                                             任意机器 / VPS 运行容器
```

为什么这样做：源码构建（Vue + Go）峰值吃 1~2GB 内存，1GB 小鸡直接构建会 OOM。
云端构建把这份负担交给 GitHub 免费的 runner，服务器只负责运行。

---

## 一、一次性设置

### 1. Fork 官方仓库

在 GitHub 上 fork `https://github.com/Wei-Shaw/sub2api` 到你的账号，得到
`https://github.com/<你>/sub2api`。

### 2. 把带改动的本地仓库指向你的 fork 并推送

```bash
# 在本地仓库根目录
git remote set-url origin https://github.com/<你>/sub2api.git
git add -A
git commit -m "chore: align Claude OAuth client_id + add GHCR build/deploy"
git push -u origin main
```

推送后，GitHub 仓库的 **Actions** 标签页会自动开始构建。构建完成后，镜像出现在仓库
右侧 **Packages** 里：`ghcr.io/<你>/sub2api:latest`。

### 3.（可选）把镜像设为 Public

GHCR 包默认私有。若设为 Public，其它机器 `docker pull` 无需登录：
仓库 → Packages → sub2api → Package settings → Change visibility → Public。

若保持 Private，则每台部署机执行一次登录（PAT 需勾选 `read:packages`）：

```bash
echo <你的PAT> | docker login ghcr.io -u <你的GitHub用户名> --password-stdin
```

---

## 二、在任意机器部署

```bash
# 1. 只需要 deploy 目录里的这两个文件即可：docker-compose.ghcr.yml 和 .env
mkdir -p sub2api && cd sub2api
# 拷贝 deploy/docker-compose.ghcr.yml 和 deploy/.env.example 到这里

cp .env.example .env
chmod 600 .env
```

编辑 `.env`，至少设置：

```bash
SUB2API_IMAGE=ghcr.io/<你>/sub2api:latest
SERVER_PORT=8090            # 选一个空闲端口（8080 常被占用）
POSTGRES_PASSWORD=<openssl rand -hex 32>
JWT_SECRET=<openssl rand -hex 32>
TOTP_ENCRYPTION_KEY=<openssl rand -hex 32>
```

> `SUB2API_IMAGE` 不是内置变量，需要你在 `.env` 里新增这一行。

启动：

```bash
mkdir -p data postgres_data redis_data
docker compose -f docker-compose.ghcr.yml pull
docker compose -f docker-compose.ghcr.yml up -d
docker compose -f docker-compose.ghcr.yml logs -f sub2api
```

访问 `http://<机器IP>:<SERVER_PORT>`。管理员密码若未设置，见日志：

```bash
docker compose -f docker-compose.ghcr.yml logs sub2api | grep -i "admin password"
```

---

## 三、跟随官方更新（保留你的改动）

在你本地的 fork 仓库里：

```bash
./deploy/sync-upstream.sh            # 合并官方最新 release tag
# 或 ./deploy/sync-upstream.sh main  # 合并官方 main 分支
```

- 脚本会自动添加 `upstream` 远程、拉取并合并官方最新版本。
- 你的改动只有 `oauth.go` 一处极小 diff，通常**不会冲突**；万一冲突，按提示保留你的
  `client_id` 值后 `git add && git commit`。
- 合并完成后推送即可触发云端重建：

```bash
git push origin main
```

Actions 重建 `:latest` 后，各部署机拉新镜像并重启：

```bash
docker compose -f docker-compose.ghcr.yml pull
docker compose -f docker-compose.ghcr.yml up -d
```

数据在 `postgres_data/` / `data/` 目录里，升级镜像不会丢数据。

---

## 四、常见问题

- **构建失败（Actions 红叉）**：点开日志看具体步骤；多为上游依赖变动，通常重跑或再同步一次即可。
- **`docker pull` 报 denied**：包是 Private 且未登录，执行上面的 `docker login ghcr.io`。
- **端口冲突**：改 `.env` 里的 `SERVER_PORT` 为空闲端口。
- **确认改动生效**：进后台加一个 Claude(anthropic) 账号，用 refresh_token 导入并刷新，
  不再报 `invalid_client` 即说明 `dae2cad8` 已编入镜像。
