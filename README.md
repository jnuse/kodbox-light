# Kodbox Image

自建 Kodbox 镜像：PHP 8.5 + Alpine + Nginx + PHP-FPM，SQLite，无 Redis。源码外部挂载。

## 变体

| Tag | 扩展集 | 说明 |
| --- | --- | --- |
| `latest` | recommended | gd、zip、pdo_sqlite、exif、intl |
| `latest-required` | required | gd、zip、pdo_sqlite |

内存 ≤256M 建议用 `latest-required`，`intl` 会让每个 PHP worker 多占用约 15–20MB。

多架构：`linux/amd64`、`linux/arm64`。

## 部署

1. 宿主机准备 Kodbox 源码目录：

   ```bash
   mkdir -p /path/to/kodbox
   # 下载 Kodbox zip 并解压到该目录，确保 index.php 在根目录
   chown -R 82:82 /path/to/kodbox