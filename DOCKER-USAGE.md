# PHP-FPM Docker 安全部署使用指南

基于 CIS Docker Benchmark 标准的 PHP-FPM 安全容器化部署方案。

> 📖 本文档为 Docker 使用教程，适用于直接拉取预构建镜像进行部署。
> 如需了解编译构建流程，请参阅 [编译构建教程](README.md)。

## 目录

- [快速开始](#快速开始)
- [使用预构建镜像（推荐）](#使用预构建镜像推荐)
- [卷挂载说明](#卷挂载说明)
- [PHP 配置说明](#php-配置说明)
- [与 Nginx 集成](#与-nginx-集成)
- [PHP 扩展管理](#php-扩展管理)
- [日常运维](#日常运维)
- [常见问题](#常见问题)

---

## 快速开始

```bash
# 1. 创建工作目录
mkdir php-docker && cd php-docker

# 2. 下载 docker-compose.ghcr.yml（或从仓库复制）
# 修改 image 为你的镜像地址

# 3. 启动容器
docker compose -f docker-compose.ghcr.yml up -d

# 4. 验证
docker exec php php -v
docker exec php php -m
```

## 使用预构建镜像（推荐）

### 步骤 1：登录 Docker Hub（私有仓库需要）

如果镜像仓库是公开的，可跳过此步骤。

```bash
echo "你的TOKEN" > ~/.dockerhub_token
cat ~/.dockerhub_token | docker login -u 你的DockerHub用户名 --password-stdin
rm ~/.dockerhub_token
```

### 步骤 2：配置 docker-compose.ghcr.yml

修改 `image` 为你的镜像地址：

```yaml
services:
  php:
    image: ihccccom/php-fpm:latest
```

### 步骤 3：启动

```bash
docker compose -f docker-compose.ghcr.yml up -d

# 查看状态
docker compose -f docker-compose.ghcr.yml ps

# 查看日志
docker compose -f docker-compose.ghcr.yml logs -f php
```

### 步骤 4：验证

```bash
# 查看 PHP 版本
docker exec php php -v

# 查看已加载扩展
docker exec php php -m

# 查看容器状态
docker ps
```

## 卷挂载说明

| 卷名 | 容器路径 | 说明 |
|------|---------|------|
| `php-conf` | `/opt/php/etc` | PHP 配置文件（php.ini、php-fpm.conf、www.conf） |
| `php-logs` | `/opt/php/var/log` | PHP-FPM 日志文件 |
| `wwwroot` | `/www/wwwroot` | 网站根目录（与 Nginx 共享） |

### 查看卷位置

```bash
docker volume inspect php-conf
```

### 编辑配置文件

```bash
# 方法1：进入容器
docker exec -it php /bin/bash

# 方法2：从宿主机复制
docker cp php:/opt/php/etc/php.ini ./php.ini
# 编辑后复制回去
docker cp ./php.ini php:/opt/php/etc/php.ini
# 重启 PHP-FPM
docker restart php
```

---

## PHP 配置说明

### 配置文件结构

```
/opt/php/
├── etc/
│   ├── php.ini                       # PHP 主配置文件
│   ├── php-fpm.conf                  # PHP-FPM 主配置
│   ├── php-fpm.d/
│   │   └── www.conf                  # 进程池配置
│   └── conf.d/
│       ├── 10-opcache.ini            # OPcache 扩展
│       ├── 20-redis.ini              # Redis 扩展
│       ├── 20-memcached.ini          # Memcached 扩展
│       └── 20-imagick.ini            # ImageMagick 扩展
├── var/
│   ├── log/
│   │   ├── php-fpm.log              # PHP-FPM 日志
│   │   ├── php_error.log            # PHP 错误日志
│   │   └── php-fpm-slow.log         # 慢日志
│   └── run/
│       └── php-fpm.pid              # PID 文件
├── bin/
│   └── php                           # PHP CLI
├── sbin/
│   └── php-fpm                       # PHP-FPM 二进制
└── lib/
    └── php/
        └── extensions/               # PHP 扩展库
```

### 默认配置特性

- **安全加固**：`expose_php=Off`、`disable_functions` 已配置危险函数、`allow_url_include=Off`
- **性能优化**：OPcache 已启用（含 JIT）、`memory_limit=256M`
- **生产配置**：`display_errors=Off`、`log_errors=On`
- **文件上传**：`upload_max_filesize=50M`、`post_max_size=50M`
- **时区**：`date.timezone=Asia/Shanghai`

---

## 与 Nginx 集成

### 方式一：Docker 网络通信（推荐）

确保 Nginx 和 PHP-FPM 容器在同一个 Docker 网络中：

```yaml
# Nginx docker-compose 中添加 depends_on
services:
  nginx:
    depends_on:
      - php

  php:
    image: ihccccom/php-fpm:latest
    volumes:
      - wwwroot:/www/wwwroot
    networks:
      - nginx-network
```

Nginx 站点配置使用 TCP 连接：

```nginx
location ~ [^/]\.php(/|$) {
    try_files $uri =404;
    fastcgi_pass php:36000;
    fastcgi_index index.php;
    include fastcgi.conf;
    include php/pathinfo.conf;
}
```

### 方式二：使用 Unix Socket

如果需要通过 Unix Socket 通信，可以共享 socket 文件：

```yaml
volumes:
  - php-run:/run/php
```

修改 `www.conf`：
```ini
listen = /run/php/php-fpm.sock
```

---

## PHP 扩展管理

### 查看已加载扩展

```bash
docker exec php php -m
```

### 内置扩展列表

以下扩展在编译时可通过构建参数 `USE_xxx=true/false` 单独启用或禁用（默认全部启用）：

| 扩展 | 构建参数 | 默认 | 说明 |
|------|---------|------|------|
| mysqlnd / mysqli / pdo_mysql | `USE_mysql=true` | 启用 | MySQL Native Driver |
| pgsql / pdo_pgsql | `USE_pgsql=true` | 启用 | PostgreSQL 接口 |
| openssl | `USE_openssl=true` | 启用 | OpenSSL 加密 |
| sodium | `USE_sodium=true` | 启用 | 加密库（libsodium） |
| password_argon2 | `USE_argon2=true` | 启用 | Argon2 密码哈希 |
| zlib | `USE_zlib=true` | 启用 | Zlib 压缩 |
| zip | `USE_zip=true` | 启用 | ZIP 压缩 |
| bz2 | `USE_bz2=true` | 启用 | BZip2 压缩 |
| curl | `USE_curl=true` | 启用 | cURL 网络库 |
| ftp | `USE_ftp=true` | 启用 | FTP 协议支持 |
| ldap | `USE_ldap=true` | 启用 | LDAP 目录服务 |
| soap | `USE_soap=true` | 启用 | SOAP 协议 |
| sockets | `USE_sockets=true` | 启用 | 套接字 |
| gd | `USE_gd=true` | 启用 | 图像处理（JPEG/PNG/WebP/AVIF） |
| exif | `USE_exif=true` | 启用 | 图像元数据 |
| mbstring | `USE_mbstring=true` | 启用 | 多字节字符串 |
| intl | `USE_intl=true` | 启用 | 国际化 |
| gettext | `USE_gettext=true` | 启用 | 多语言翻译 |
| xsl | `USE_xsl=true` | 启用 | XSL 转换 |
| tidy | `USE_tidy=true` | 启用 | HTML 清理 |
| bcmath | `USE_bcmath=true` | 启用 | 任意精度数学 |
| gmp | `USE_gmp=true` | 启用 | 大数运算 |
| pcntl | `USE_pcntl=true` | 启用 | 进程控制 |
| shmop | `USE_shmop=true` | 启用 | 共享内存操作 |
| sysvmsg | `USE_sysvmsg=true` | 启用 | System V 消息队列 |
| sysvsem | `USE_sysvsem=true` | 启用 | System V 信号量 |
| sysvshm | `USE_sysvshm=true` | 启用 | System V 共享内存 |
| calendar | `USE_calendar=true` | 启用 | 日历函数 |
| readline | `USE_readline=true` | 启用 | Readline 交互式终端 |
| mhash | `USE_mhash=true` | 启用 | MHash 哈希函数 |
| pear | `USE_pear=true` | 启用 | PEAR 包管理器 |
| opcache | `USE_opcache=true` | 启用 | OPcache 字节码缓存 |

### 可选 PECL 扩展

| 扩展 | 构建参数 | 默认 |
|------|---------|------|
| Redis | `USE_redis=true` | 启用 |
| Memcached | `USE_memcached=true` | 启用 |
| ImageMagick | `USE_imagick=true` | 启用 |
| MongoDB | `USE_mongodb=true` | 禁用 |
| Swoole | `USE_swoole=true` | 禁用 |

---

## 日常运维

### 重启 PHP-FPM

```bash
docker restart php
```

### 查看日志

```bash
# PHP-FPM 日志
docker exec php tail -f /opt/php/var/log/php-fpm.log

# PHP 错误日志
docker exec php tail -f /opt/php/var/log/php_error.log

# 慢日志
docker exec php tail -f /opt/php/var/log/php-fpm-slow.log

# Docker 容器日志
docker logs -f php
```

### 测试配置

```bash
docker exec php php-fpm -t
```

### 查看 PHP 信息

```bash
# 完整 phpinfo
docker exec php php -i

# PHP 版本
docker exec php php -v

# 已加载扩展
docker exec php php -m
```

### 备份配置

```bash
for vol in php-conf php-logs; do
  docker run --rm -v ${vol}:/data -v $(pwd)/backup:/backup \
    alpine tar czf /backup/${vol}.tar.gz -C /data .
done
```

### 更新镜像

```bash
# 拉取最新镜像
docker compose -f docker-compose.ghcr.yml pull

# 重新创建容器（卷数据保留）
docker compose -f docker-compose.ghcr.yml up -d
```

---

## 常见问题

### Q: 容器启动后立即退出

**A**: 检查日志 `docker logs php`，常见原因：
1. PHP-FPM 配置语法错误
2. 扩展依赖库缺失
3. 文件权限不正确

### Q: PHP-FPM 连接超时

**A**: 确认 Nginx 和 PHP-FPM 在同一 Docker 网络中：
```bash
docker network ls
docker network inspect nginx-network
```

### Q: 上传文件大小限制

**A**: 修改 `php.ini` 中的以下配置：
```ini
upload_max_filesize = 100M
post_max_size = 100M
```
同时修改 Nginx 的 `client_max_body_size`。

### Q: 内存不足

**A**: 修改 `php.ini` 中的 `memory_limit`：
```ini
memory_limit = 512M
```

### Q: 如何进入容器调试

```bash
docker exec -it php /bin/bash
```

---

## 镜像版本标签

| 标签格式 | 触发条件 | 示例 |
|---------|---------|------|
| `latest` | 推送到 main 分支 | `php-fpm:latest` |
| `v1.0.0` | 创建 v1.0.0 标签 | `php-fpm:v1.0.0` |
| `1.0` | 创建 v1.0.x 标签 | `php-fpm:1.0` |
| `php-8.4.15` | 所有构建 | `php-fpm:php-8.4.15` |
