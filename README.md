# PHP-FPM Docker 安全部署方案

基于 CIS Docker Benchmark 标准的 PHP-FPM 安全容器化部署方案。

## 目录

- [项目概述](#项目概述)
- [目录结构](#目录结构)
- [快速开始](#快速开始)
- [部署教程](#部署教程)
  - [GitHub Actions 构建与 Docker Hub 拉取教程](#github-actions-构建与-docker-hub-拉取教程)
  - [本地构建教程](#本地构建教程)
- [构建参数](#构建参数)
- [卷挂载说明](#卷挂载说明)
- [与 Nginx 集成](#与-nginx-集成)
- [常见问题](#常见问题)
- [许可证](#许可证)

---

## 项目概述

本项目提供一套**生产级**的 PHP-FPM Docker 安全部署方案，目标是：

- ✅ 通过 **CIS Docker Benchmark** 安全检查
- ✅ 源码编译 PHP-FPM，灵活控制扩展和编译选项
- ✅ 实施 **纵深防御**：Capabilities 限制 + 非 root 运行 + 只读文件系统
- ✅ 支持多种 PECL 扩展（Redis、Memcached、ImageMagick、MongoDB、Swoole）
- ✅ 生产环境优化配置（OPcache JIT、安全 php.ini）
- ✅ 与 Nginx 容器无缝集成

**核心安全特性**：

| 安全层面 | 实现方式 | 效果 |
|---------|---------|------|
| 容器级防护 | 非 root + 只读文件系统 + Capabilities 限制 | 最小权限原则 |
| 应用级防护 | disable_functions + expose_php=Off + 安全 php.ini | 减少攻击面 |
| 运维级防护 | 健康检查 + 日志收集 + 资源限制 | 安全运维 |

## 目录结构

```
.github/
└── workflows/
    └── docker-build-push-php.yml      # GitHub Actions 构建并发布到 Docker Hub

php/
├── Dockerfile                         # 多阶段 Docker 构建（源码编译 PHP-FPM）
├── docker-compose.yml                 # Docker Compose - 本地构建用
├── docker-compose.ghcr.yml            # Docker Compose - 拉取 Docker Hub 预构建镜像用
├── docker-entrypoint.sh               # 容器入口脚本（权限检查）
├── .dockerignore                      # 构建上下文排除规则
├── README.md                          # 📖 编译构建教程（本文件）
├── DOCKER-USAGE.md                    # 📖 Docker 使用教程（可独立发布）
│
├── conf/                              # PHP 配置文件（内置，构建时 COPY 到镜像）
│   ├── php.ini                       # PHP 主配置文件（生产优化）
│   ├── php-fpm.conf                  # PHP-FPM 主配置文件
│   └── www.conf                      # PHP-FPM 进程池配置
│
├── deploy/                            # 部署包（可发布到其他仓库供用户使用）
│   ├── README.md                     # Docker 使用教程
│   ├── DOCKER-USAGE.md               # Docker 使用详细教程
│   └── docker-compose.yml            # 用户部署用 Compose 文件
│
└── tests/
    ├── validate.sh                   # 自动化安全验证脚本
    └── README.md                     # 📖 测试说明
```

## 快速开始

> 📖 **Docker 使用教程**（部署、配置、运维）已独立为 **[DOCKER-USAGE.md](DOCKER-USAGE.md)**，方便发布到其他仓库供用户使用。

### 方式一：使用预构建镜像（推荐 - 从 Docker Hub 拉取）

镜像由 GitHub Actions 自动构建并发布到 Docker Hub，无需本地编译。

```bash
cd php

# 拉取并启动（需先修改 docker-compose.ghcr.yml 中的镜像地址）
docker compose -f docker-compose.ghcr.yml up -d

# 查看容器状态
docker compose -f docker-compose.ghcr.yml ps

# 查看日志
docker compose -f docker-compose.ghcr.yml logs -f php
```

### 方式二：本地构建

在本地从源码编译 PHP-FPM 及所有扩展（编译耗时约 10-20 分钟）。

```bash
cd php

# 构建镜像
docker compose build

# 启动容器
docker compose up -d
```

### 验证部署

```bash
# 运行安全验证脚本
bash tests/validate.sh

# 查看 PHP 版本
docker exec php php -v

# 查看已加载扩展
docker exec php php -m

# 查看 PHP 配置
docker exec php php -i
```

### 查看日志

```bash
docker logs php
```

---

## 部署教程

### GitHub Actions 构建与 Docker Hub 拉取教程

#### 概述

本项目提供 GitHub Actions 工作流（`.github/workflows/docker-build-push-php.yml`），自动编译 PHP-FPM Docker 镜像并发布到 Docker Hub。

**优势**：
- ✅ 无需本地编译，节省时间和资源
- ✅ 自动化构建，每次代码更新自动发布新镜像
- ✅ 支持多架构（amd64/arm64）
- ✅ 支持版本标签管理

#### 步骤 1：配置 GitHub Secrets

在仓库 **Settings** → **Secrets and variables** → **Actions** 中添加：

| Secret 名称 | 说明 |
|-------------|------|
| `DOCKERHUB_USERNAME` | Docker Hub 用户名（例如 `ihccccom`） |
| `DOCKERHUB_TOKEN` | Docker Hub Access Token（在 Docker Hub → Account Settings → Security 中创建） |

> ⚠️ 三个镜像（Nginx、PHP-FPM、Redis）共用同一组 Secrets，只需配置一次。

#### 步骤 2：触发构建

构建会在以下情况自动触发：
- 推送到 `main` 分支且 `php/` 目录有变更
- 创建版本标签（如 `v1.0.0`）

也可以手动触发：
1. 进入仓库页面 → **Actions** → **Build and Push PHP-FPM Docker Image**
2. 点击 **Run workflow**
3. 可选择配置 PHP 版本、启用/禁用扩展等
4. 点击 **Run workflow** 开始构建

#### 步骤 3：本地拉取并运行

```bash
cd php

# 使用 docker-compose.ghcr.yml
docker compose -f docker-compose.ghcr.yml up -d

# 或手动拉取并运行
docker pull ihccccom/php-fpm:latest
docker run -d --name php-fpm ihccccom/php-fpm:latest
```

#### 版本标签说明

| 标签格式 | 触发条件 | 示例 |
|---------|---------|------|
| `latest` | 推送到 main 分支 | `php-fpm:latest` |
| `v1.0.0` | 创建 v1.0.0 标签 | `php-fpm:v1.0.0` |
| `1.0` | 创建 v1.0.x 标签 | `php-fpm:1.0` |
| `php-8.5.3` | 所有构建 | `php-fpm:php-8.5.3` |

---

### 本地构建教程

#### 概述

在本地从源码编译构建 PHP-FPM Docker 镜像，适用于需要自定义编译选项或无法访问 Docker Hub 的场景。

**注意**：编译过程需要下载源码并编译，首次构建耗时约 **10-20 分钟**。

#### 步骤 1：克隆仓库

```bash
git clone https://github.com/mzwrt/copilot.git
cd copilot/php
```

#### 步骤 2：（可选）自定义构建参数

编辑 `docker-compose.yml`，取消注释并修改 `args` 部分：

```yaml
services:
  php:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        PHP_VERSION: "8.5.3"
        USE_redis: "true"
        USE_imagick: "true"
        USE_swoole: "true"
```

或者通过命令行传入构建参数：

```bash
docker compose build --build-arg USE_swoole=true --build-arg USE_mongodb=true
```

#### 步骤 3：构建镜像

```bash
# 使用 docker compose 构建
docker compose build

# 或直接使用 docker build
docker build -t php-fpm:latest .
```

#### 步骤 4：启动容器

```bash
docker compose up -d
docker compose ps
docker compose logs -f php
```

#### 步骤 5：验证

```bash
# 查看 PHP 版本
docker exec php php -v

# 查看已加载扩展
docker exec php php -m

# 运行安全检查
bash tests/validate.sh
```

## 构建参数

### 内置模块开关（全部默认启用，按需关闭以减少攻击面）

| 参数 | 默认值 | 说明 |
|------|--------|------|
| **数据库模块** | | |
| `USE_mysql` | `true` | MySQL/MariaDB 支持（mysqlnd + mysqli + pdo_mysql） |
| `USE_pgsql` | `true` | PostgreSQL 支持（pgsql + pdo_pgsql） |
| **加密与安全模块** | | |
| `USE_openssl` | `true` | OpenSSL 加密支持 |
| `USE_sodium` | `true` | Sodium 加密库（libsodium） |
| `USE_argon2` | `true` | Argon2 密码哈希 |
| **压缩模块** | | |
| `USE_zlib` | `true` | Zlib 压缩 |
| `USE_zip` | `true` | ZIP 压缩 |
| `USE_bz2` | `true` | BZip2 压缩 |
| **网络与协议模块** | | |
| `USE_curl` | `true` | cURL 网络库 |
| `USE_ftp` | `true` | FTP 协议支持 |
| `USE_ldap` | `true` | LDAP 目录服务 |
| `USE_soap` | `true` | SOAP 协议 |
| `USE_sockets` | `true` | 套接字支持 |
| **图像处理模块** | | |
| `USE_gd` | `true` | GD 图像库（含 JPEG/PNG/WebP/AVIF） |
| `USE_exif` | `true` | 图像 EXIF 元数据 |
| **文本与国际化模块** | | |
| `USE_mbstring` | `true` | 多字节字符串（UTF-8 必需） |
| `USE_intl` | `true` | 国际化扩展 |
| `USE_gettext` | `true` | Gettext 多语言支持 |
| `USE_xsl` | `true` | XSL 转换 |
| `USE_tidy` | `true` | HTML Tidy 清理 |
| **数学模块** | | |
| `USE_bcmath` | `true` | BCMath 任意精度数学 |
| `USE_gmp` | `true` | GMP 大数运算 |
| **系统与进程模块** | | |
| `USE_pcntl` | `true` | 进程控制 |
| `USE_shmop` | `true` | 共享内存操作 |
| `USE_sysvmsg` | `true` | System V 消息队列 |
| `USE_sysvsem` | `true` | System V 信号量 |
| `USE_sysvshm` | `true` | System V 共享内存 |
| **其他内置模块** | | |
| `USE_calendar` | `true` | 日历函数 |
| `USE_readline` | `true` | Readline 交互式终端 |
| `USE_mhash` | `true` | MHash 哈希函数 |
| `USE_pear` | `true` | PEAR 包管理器 |

### 第三方扩展开关

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `USE_redis` | `true` | 启用 Redis 扩展 |
| `USE_memcached` | `true` | 启用 Memcached 扩展 |
| `USE_imagick` | `true` | 启用 ImageMagick 扩展 |
| `USE_mongodb` | `false` | 启用 MongoDB 扩展 |
| `USE_swoole` | `false` | 启用 Swoole 扩展 |
| `USE_opcache` | `true` | 启用 OPcache 扩展（含 JIT） |
| `USE_snuffleupagus` | `false` | 启用 Snuffleupagus 安全扩展（运行时 PHP 防护） |

### 版本配置（留空自动获取最新版）

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `PHP_VERSION` | `8.5.3` | PHP 版本号（必须指定） |
| `REDIS_VERSION` | `""` | Redis 扩展版本，留空自动获取最新版 |
| `MEMCACHED_VERSION` | `""` | Memcached 扩展版本，留空自动获取最新版 |
| `IMAGICK_VERSION` | `""` | ImageMagick 扩展版本，留空自动获取最新版 |
| `MONGODB_VERSION` | `""` | MongoDB 扩展版本，留空自动获取最新版 |
| `SWOOLE_VERSION` | `""` | Swoole 扩展版本，留空自动获取最新版 |
| `SNUFFLEUPAGUS_VERSION` | `""` | Snuffleupagus 版本，留空使用最新版 |

### 其他配置

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `EXTRA_PHP_EXTENSIONS` | `""` | 额外 PHP 编译配置参数 |

**自定义构建示例**：

```bash
# 基本构建（全部模块启用）
docker build -t php-fpm:latest ./php/

# 最小化构建（仅保留核心模块）
docker build \
  --build-arg USE_pgsql=false \
  --build-arg USE_ldap=false \
  --build-arg USE_ftp=false \
  --build-arg USE_soap=false \
  --build-arg USE_gmp=false \
  --build-arg USE_tidy=false \
  --build-arg USE_xsl=false \
  --build-arg USE_calendar=false \
  --build-arg USE_shmop=false \
  --build-arg USE_sysvmsg=false \
  --build-arg USE_sysvsem=false \
  --build-arg USE_sysvshm=false \
  -t php-fpm:minimal ./php/

# 启用 Swoole
docker build --build-arg USE_swoole=true -t php-fpm:latest ./php/

# 启用 Snuffleupagus 安全扩展
docker build --build-arg USE_snuffleupagus=true -t php-fpm:latest ./php/

# 指定 PHP 版本
docker build --build-arg PHP_VERSION=8.3.15 -t php-fpm:latest ./php/

# 禁用 ImageMagick
docker build --build-arg USE_imagick=false -t php-fpm:latest ./php/

# 禁用 MySQL，仅使用 PostgreSQL
docker build --build-arg USE_mysql=false -t php-fpm:latest ./php/
```

## 卷挂载说明

| 卷名 | 容器路径 | 说明 |
|------|---------|------|
| `php-conf` | `/opt/php/etc` | PHP 配置文件（php.ini、php-fpm.conf、www.conf） |
| `php-logs` | `/opt/php/var/log` | PHP-FPM 日志文件 |
| `wwwroot` | `/www/wwwroot` | 网站根目录（与 Nginx 共享） |

## 与 Nginx 集成

PHP-FPM 容器需要与 Nginx 容器配合使用。两个容器通过 Docker 网络通信。

### 网络配置

PHP-FPM 和 Nginx 容器需要在同一个 Docker 网络中：

```yaml
# nginx/docker-compose.yml 中
networks:
  - nginx-network

# php/docker-compose.yml 中
networks:
  - nginx-network
```

### Nginx 配置

在 Nginx 站点配置中使用 `fastcgi_pass php:36000` 将 PHP 请求转发到 PHP-FPM 容器：

```nginx
location ~ [^/]\.php(/|$) {
    try_files $uri =404;
    fastcgi_pass php:36000;
    fastcgi_index index.php;
    include fastcgi.conf;
    include php/pathinfo.conf;
}
```

### 共享网站根目录

两个容器需要挂载相同的 `wwwroot` 卷：

```yaml
# 两个容器都需要：
volumes:
  - wwwroot:/www/wwwroot
```

## 常见问题

### Q: 容器启动后立即退出

**A**: 检查日志 `docker logs php`，常见原因：
1. PHP-FPM 配置语法错误
2. 扩展依赖库缺失
3. 文件权限不正确

### Q: PHP-FPM 连接被拒绝

**A**: 确保 Nginx 和 PHP-FPM 在同一 Docker 网络：
```bash
docker network ls
docker network inspect nginx-network
```

### Q: 如何查看已编译的扩展

```bash
docker exec php php -m
```

### Q: 如何查看 PHP 配置

```bash
docker exec php php -i
```

### Q: 如何进入容器调试

```bash
docker exec -it php /bin/bash
```

### Q: OPcache JIT 不工作

**A**: 确保 `USE_opcache=true` 构建参数已启用，且 `php.ini` 中已配置：
```ini
opcache.jit = tracing
opcache.jit_buffer_size = 64M
```

## 许可证

本项目遵循 [MIT License](../LICENSE)。
