# Kodbox Image

自建 Kodbox 镜像：PHP + Alpine + Nginx + PHP-FPM，SQLite 数据库，无 Redis。

源码通过卷挂载进容器，镜像本身不含 Kodbox 代码。镜像只负责 PHP 运行时、Nginx、扩展和配置。

## 目录

1. [镜像变体](#镜像变体)
2. [前置条件](#前置条件)
3. [准备 Kodbox 源码](#准备-kodbox-源码)
4. [部署](#部署)
5. [首次安装](#首次安装)
6. [后台建议配置](#后台建议配置)
7. [升级镜像](#升级镜像)
8. [切换扩展集](#切换扩展集)
9. [故障排查](#故障排查)

---

## 镜像变体

| Tag | 扩展集 | 说明 |
| --- | --- | --- |
| `latest` | recommended | gd、zip、pdo_sqlite、exif、intl |
| `latest-required` | required | gd、zip、pdo_sqlite |

两个 tag 都支持 `linux/amd64` 和 `linux/arm64`。

**选哪个**：

- 容器内存限制 **<256M**：用 `latest-required`。`intl` 扩展会让每个 PHP worker 多占用约 15–20MB，更低的限制下容易 OOM。
- 容器内存 **≥512M**：用 `latest`。`intl` 提升解压和 CSS 解析性能，`exif` 支持读取图片元信息。

---

## 前置条件

- 已安装 Docker 和 docker compose。
- 宿主机上有约 1GB 空闲磁盘用于 Kodbox 源码和文件存储。
- 能访问 `ghcr.io`（拉取镜像）。

确认 docker compose 可用：

```bash
docker compose version
```

---

## 准备 Kodbox 源码

容器不包含 Kodbox 代码，所以第一步是在宿主机上准备好源码目录。

### 1. 创建目录

```bash
mkdir -p /srv/kodbox
cd /srv/kodbox
```

路径可以换成你喜欢的，后文用 `/srv/kodbox` 举例。

### 2. 下载并解压

去官方下载页获取最新版：

```bash
# 以 1.70 为例，版本号请替换为实际最新版
curl -fSL -o kodbox.zip https://static.kodcloud.com/update/download/kodbox.1.70.zip
unzip kodbox.zip
rm kodbox.zip
```

解压后确认入口文件存在：

```bash
ls -l /srv/kodbox/index.php
```

**必须看到 `index.php` 在 `/srv/kodbox/` 根目录下**。如果解压多套了一层目录（比如 `/srv/kodbox/kodbox/index.php`），把里层内容移到外层：

```bash
mv /srv/kodbox/kodbox/* /srv/kodbox/kodbox/.[!.]* /srv/kodbox/ 2>/dev/null
rmdir /srv/kodbox/kodbox
```

### 3. 创建数据目录

Kodbox 需要 `data/` 和 `config/` 两个可写目录：

```bash
mkdir -p /srv/kodbox/data /srv/kodbox/config
```

### 4. 修正所有者

容器内 `www-data` 的 UID/GID 是 **82:82**（Alpine 默认）。宿主机上需要把源码目录交给这个 UID，否则容器内 PHP 无法写入。

```bash
chown -R 82:82 /srv/kodbox
```

**先检查 82 是否已被占用**：

```bash
getent passwd 82
```

- **无输出**：82 空闲，直接 `chown 82:82`，安全。
- **有输出**（比如 `bin:x:82:82:...`）：说明宿主机上已有 UID 82 的用户。`chown 82:82` 会让该用户对 Kodbox 目录也有权限。如果这个用户没有登录权限（如 `bin`），风险可接受；如果你介意，可以在构建镜像时把 `www-data` 改成其他 UID（见[故障排查](#故障排查)中的“UID 冲突”一节）。

---

## 部署

### 1. 获取 compose 文件

如果仓库已克隆到宿主机：

```bash
cd kodbox-light
```

如果只有镜像没有仓库，创建一个 `compose.yaml`：

```yaml
services:
  kodbox:
    image: ghcr.io/jnuse/kodbox-light:latest
    container_name: kodbox
    restart: unless-stopped
    ports:
      - "8080:80"
    volumes:
      - /srv/kodbox:/var/www/html
    environment:
      TZ: Asia/Shanghai
    mem_limit: 256m
```

`/srv/kodbox` 换成你实际的源码路径。

### 2. 启动

```bash
docker compose up -d
```

### 3. 确认启动成功

```bash
docker compose ps
```

应看到 `kodbox` 状态为 `Up`。

查看日志：

```bash
docker compose logs -f kodbox
```

正常日志中会看到 Nginx 启动信息和 PHP-FPM 的 `ready to handle connections`。

如果日志出现：

```
ERROR: /var/www/html/index.php not found.
Kodbox source must be mounted at /var/www/html.
```

说明源码没挂载对，回到[准备 Kodbox 源码](#准备-kodbox-源码)检查 `index.php` 位置和 compose 里的路径。

---

## 首次安装

1. 浏览器访问 `http://<宿主机IP>:8080`。
2. 安装向导选择 **SQLite**。
3. 设置管理员账号和密码。
4. 完成安装后，用管理员账号登录。

安装向导会检查 PHP 扩展和目录权限。如果提示某个扩展缺失，对照[镜像变体](#镜像变体)确认你用的 tag 是否包含该扩展；如果提示目录不可写，回到[修正所有者](#4-修正所有者)检查 `chown`。

---

## 后台建议配置

登录管理员账号后，进入 **系统设置**：

### 上传/下载

**系统设置 → 基础设置 → 上传/下载**

- **分片大小**：设为 **5M**。
- **上传并发数量**：设为 **15**。

分片大小必须小于 Nginx 的 `client_max_body_size`（本镜像设为 2048M）和 PHP 的 `post_max_size`（设为 512M）。5M 远小于这两个值，安全。

### HTTPS

本镜像只监听 HTTP。如果你需要 HTTPS，在 Kodbox 容器前面再加一层反向代理（Nginx、Caddy、Traefik 均可），由它负责 TLS 终止，把请求转发到 `kodbox:80`。

---

## 升级镜像

镜像本身（PHP 版本、扩展、Nginx 配置）更新时：

```bash
docker compose pull
docker compose up -d
```

`docker compose up -d` 会检测到镜像变化并重建容器。源码在宿主机上，不受影响；`data/` 和 `config/` 也在宿主机上，不受影响。

---

## 切换扩展集

从 `latest`（recommended）切到 `latest-required`：

```yaml
services:
  kodbox:
    image: ghcr.io/jnuse/kodbox-light:latest-required
```

```bash
docker compose up -d
```

反向切换同理。切换后扩展集合变化，建议重启一次容器确保干净：

```bash
docker compose restart kodbox
```

---

## 故障排查

### 容器启动后日志报 `index.php not found`

源码没挂载到 `/var/www/html`，或者挂载路径不对。检查：

```bash
# 宿主机上
ls /srv/kodbox/index.php

# compose 里的 volumes 路径
grep -A2 volumes compose.yaml
```

### 页面 500，日志里有 `Permission denied`

宿主机目录所有者不对。执行：

```bash
chown -R 82:82 /srv/kodbox
```

### 页面 502 Bad Gateway

PHP-FPM 没起来或 socket 不通。查看日志：

```bash
docker compose logs kodbox | grep -i fpm
```

常见原因是 `/run` 目录权限异常。重启容器通常能恢复：

```bash
docker compose restart kodbox
```

### 上传大文件失败

按顺序检查三处限制：

1. **Kodbox 后台**：分片大小是否 ≤5M。
2. **Nginx**：`client_max_body_size` 是否 ≥ 分片大小（本镜像 2048M）。
3. **PHP**：`post_max_size`、`upload_max_filesize` 是否 ≥ 分片大小（本镜像 512M）。

分片上传时单次请求大小等于分片大小，所以只要分片 ≤5M，512M/2048M 的上限都不会触发。

### 容器因 OOM 被杀

```bash
docker events --filter container=kodbox --filter event=oom
```

有输出说明内存不够。处理方式：

- 切换到 `latest-required`（去掉 `intl`）。
- 或降低 compose 里 `mem_limit` 之外的 PHP-FPM 进程数：手动改镜像内的 `www.conf` 不推荐，更简单的做法是提高 `mem_limit` 到 512M。

### UID 冲突

宿主机上 UID 82 已被占用，且你不想让它共享 Kodbox 目录权限。两种处理：

**方案 A：换一个宿主机上空闲的 UID**

1. 在 Dockerfile 中加：

   ```dockerfile
   RUN sed -i 's/^www-data:x:82:82:/www-data:x:2000:2000:/' /etc/passwd && \
       sed -i 's/^www-data:x:82:/www-data:x:2000:/' /etc/group
   ```

2. 重新构建镜像。
3. 宿主机上 `chown -R 2000:2000 /srv/kodbox`。

**方案 B：接受共享**

如果 UID 82 对应的系统用户没有登录 shell（如 `bin`、`daemon`），共享权限的实际风险很低，直接 `chown -R 82:82` 即可。

### 确认容器内存限制生效

```bash
docker stats kodbox --no-stream
```

`MEM LIMIT` 列应显示 `256MB` 左右。如果显示的是宿主机总内存，检查 compose 文件中的 `mem_limit` 字段是否被正确加载。