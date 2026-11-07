# =======================================================
# PHP-FPM Docker 构建文件
# 基于源码编译 PHP-FPM，安全加固配置
# 符合 CIS Docker Benchmark 安全基准
# =======================================================
#
# 构建示例:
#   docker build -t php-fpm .
#   docker build --build-arg PHP_VERSION=8.5.3 -t php-fpm .
#   docker build --build-arg USE_redis=false -t php-fpm .
#   docker build --build-arg USE_mysql=false --build-arg USE_ldap=false -t php-fpm .
#
# 运行示例:
#   docker run -d --name php-fpm php-fpm
#   docker compose up -d
#

###############################################
# 内置 PHP 模块开关 (Built-in Module Toggles)
# 设置为 "true" 启用，"false" 禁用
# 构建时可通过 --build-arg 覆盖
# 按需启用以减少攻击面，提升安全性
###############################################

# --- 数据库模块 ---
ARG USE_mysql=true
ARG USE_pgsql=true

# --- 加密与安全模块 ---
ARG USE_openssl=true
ARG USE_sodium=true
ARG USE_argon2=true

# --- 压缩模块 ---
ARG USE_zlib=true
ARG USE_zip=true
ARG USE_bz2=true

# --- 网络与协议模块 ---
ARG USE_curl=true
ARG USE_ftp=true
ARG USE_ldap=true
ARG USE_soap=true
ARG USE_sockets=true

# --- 图像处理模块 ---
ARG USE_gd=true
ARG USE_exif=true

# --- 文本与国际化模块 ---
ARG USE_mbstring=true
ARG USE_intl=true
ARG USE_gettext=true
ARG USE_xsl=true
ARG USE_tidy=true

# --- 数学模块 ---
ARG USE_bcmath=true
ARG USE_gmp=true

# --- 系统与进程模块 ---
ARG USE_pcntl=true
ARG USE_shmop=true
ARG USE_sysvmsg=true
ARG USE_sysvsem=true
ARG USE_sysvshm=true

# --- 其他内置模块 ---
ARG USE_calendar=true
ARG USE_readline=true
ARG USE_mhash=true
ARG USE_pear=true

###############################################
# 第三方扩展开关 (Third-party Extension Toggles)
# 设置为 "true" 启用，"false" 禁用
# 构建时可通过 --build-arg 覆盖
###############################################

# Redis 扩展
ARG USE_redis=true

# Memcached 扩展
ARG USE_memcached=true

# ImageMagick 扩展 (imagick)
ARG USE_imagick=true

# MongoDB 扩展
ARG USE_mongodb=false

# Swoole 扩展
ARG USE_swoole=false

# OPcache 扩展（强烈推荐启用）
ARG USE_opcache=true

# Snuffleupagus 安全扩展（PHP 安全加固模块，运行时防护）
ARG USE_snuffleupagus=true

###############################################
# 版本配置 (Version Configuration)
# 留空 "" 表示自动获取最新版本
# 填写具体版本号表示使用指定版本
# 构建时可通过 --build-arg 覆盖
###############################################

# PHP 版本（必须手动指定）
ARG PHP_VERSION=8.5.12
# PHP 源码包 SHA256 校验值（与 PHP_VERSION 同步更新，留空则自动从官方 API 获取）
ARG PHP_SHA256=

# Redis 扩展版本（留空自动获取最新版）
ARG REDIS_VERSION=""

# Memcached 扩展版本（留空自动获取最新版）
ARG MEMCACHED_VERSION=""

# ImageMagick 扩展版本（留空自动获取最新版）
ARG IMAGICK_VERSION=""

# MongoDB 扩展版本（留空自动获取最新版）
ARG MONGODB_VERSION=""

# Swoole 扩展版本（留空自动获取最新版）
ARG SWOOLE_VERSION=""

# Snuffleupagus 安全扩展版本（留空使用最新版）
ARG SNUFFLEUPAGUS_VERSION=""

###############################################
# 额外 PHP 扩展入口 (Extra PHP Extensions)
# 可添加额外的 --enable 或 --with 参数
# 多个参数用空格分隔
###############################################
ARG EXTRA_PHP_EXTENSIONS=""

# =======================================================
# Stage 1: 编译阶段 (Build Stage)
# 使用完整 Debian 进行编译，最终镜像只保留运行时文件
# =======================================================
FROM debian:bookworm-slim AS builder

# hadolint ignore=DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 重新声明所有 ARGs（FROM 之后 ARG 需要重新声明）
# 内置模块开关
ARG USE_mysql
ARG USE_pgsql
ARG USE_openssl
ARG USE_sodium
ARG USE_argon2
ARG USE_zlib
ARG USE_zip
ARG USE_bz2
ARG USE_curl
ARG USE_ftp
ARG USE_ldap
ARG USE_soap
ARG USE_sockets
ARG USE_gd
ARG USE_exif
ARG USE_mbstring
ARG USE_intl
ARG USE_gettext
ARG USE_xsl
ARG USE_tidy
ARG USE_bcmath
ARG USE_gmp
ARG USE_pcntl
ARG USE_shmop
ARG USE_sysvmsg
ARG USE_sysvsem
ARG USE_sysvshm
ARG USE_calendar
ARG USE_readline
ARG USE_mhash
ARG USE_pear
# 第三方扩展开关
ARG USE_redis
ARG USE_memcached
ARG USE_imagick
ARG USE_mongodb
ARG USE_swoole
ARG USE_opcache
ARG USE_snuffleupagus
# 版本配置
ARG PHP_VERSION
ARG PHP_SHA256
ARG REDIS_VERSION
ARG MEMCACHED_VERSION
ARG IMAGICK_VERSION
ARG MONGODB_VERSION
ARG SWOOLE_VERSION
ARG SNUFFLEUPAGUS_VERSION
ARG EXTRA_PHP_EXTENSIONS

ENV DEBIAN_FRONTEND=noninteractive \
    PHP_DIR=/opt/php \
    PHP_SRC_DIR=/opt/php/src

# 安装编译依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    autoconf \
    automake \
    libtool \
    re2c \
    bison \
    pkg-config \
    wget \
    curl \
    ca-certificates \
    git \
    jq \
    libxml2-dev \
    libsqlite3-dev \
    libssl-dev \
    zlib1g-dev \
    libcurl4-openssl-dev \
    libpng-dev \
    libjpeg62-turbo-dev \
    libfreetype6-dev \
    libwebp-dev \
    libavif-dev \
    libonig-dev \
    libzip-dev \
    libsodium-dev \
    libargon2-dev \
    libreadline-dev \
    libxslt1-dev \
    libbz2-dev \
    libgmp-dev \
    libldap2-dev \
    libpq-dev \
    libmemcached-dev \
    libmagickwand-dev \
    libicu-dev \
    libevent-dev \
    libtidy-dev \
    && rm -rf /var/lib/apt/lists/*

# 创建构建目录
RUN mkdir -p ${PHP_SRC_DIR} \
    && chmod 750 ${PHP_SRC_DIR} \
    && chown root:root ${PHP_SRC_DIR}

# 下载 PHP 源码并验证 SHA256 完整性（防止供应链攻击）
# 若 PHP_SHA256 已指定则直接使用；否则从官方 releases JSON API 动态获取。
# 更新 PHP_VERSION 时请同步更新 PHP_SHA256 以确保构建稳定性。
RUN cd ${PHP_SRC_DIR} \
    && if [ -n "${PHP_SHA256}" ]; then \
         EXPECTED_HASH="${PHP_SHA256}"; \
         echo "INFO: Using hardcoded SHA256 for php-${PHP_VERSION}.tar.gz"; \
       else \
         RELEASES_JSON=$(curl -fsSL "https://www.php.net/releases/index.php?json&version=${PHP_VERSION}" 2>&1) \
         || { echo "ERROR: Failed to fetch PHP releases API for version ${PHP_VERSION} (curl exit=$?)"; echo "Curl output: ${RELEASES_JSON}"; exit 1; }; \
         if [ -z "${RELEASES_JSON}" ]; then \
           echo "ERROR: PHP releases API returned empty response for version ${PHP_VERSION}"; exit 1; \
         fi; \
         EXPECTED_HASH=$(echo "${RELEASES_JSON}" \
           | jq --arg ver "${PHP_VERSION}" -r '.source[] | select(.filename == "php-\($ver).tar.gz") | .sha256'); \
         if [ -z "${EXPECTED_HASH}" ]; then \
           echo "ERROR: PHP releases API request failed for version ${PHP_VERSION}"; exit 1; \
         fi; \
         if [ "${EXPECTED_HASH}" = "null" ]; then \
           echo "ERROR: SHA256 for php-${PHP_VERSION}.tar.gz not found in PHP releases API response"; exit 1; \
         fi; \
       fi \
    && wget --tries=5 --waitretry=2 \
       "https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz" \
    && ACTUAL_HASH=$(sha256sum "php-${PHP_VERSION}.tar.gz" | awk '{print $1}') \
    && [ "${EXPECTED_HASH}" = "${ACTUAL_HASH}" ] \
       || { echo "ERROR: PHP tarball SHA256 mismatch! expected=${EXPECTED_HASH} actual=${ACTUAL_HASH}"; exit 1; } \
    && tar -zxf "php-${PHP_VERSION}.tar.gz" \
    && mv "php-${PHP_VERSION}" php \
    && rm -f "php-${PHP_VERSION}.tar.gz" \
    && chown -R root:root ${PHP_SRC_DIR}/php

# 配置、编译、安装 PHP（根据模块开关动态生成 configure 参数）
RUN set -eux; \
    cd ${PHP_SRC_DIR}/php; \
    CONFIGURE_ARGS=""; \
    # --- 数据库模块 ---
    if [ "${USE_mysql}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --enable-mysqlnd --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd"; \
    fi; \
    if [ "${USE_pgsql}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --with-pgsql --with-pdo-pgsql"; \
    fi; \
    # --- 加密与安全模块 ---
    if [ "${USE_openssl}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --with-openssl"; \
    fi; \
    if [ "${USE_sodium}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --with-sodium"; \
    fi; \
    if [ "${USE_argon2}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --with-password-argon2"; \
    fi; \
    # --- 压缩模块 ---
    if [ "${USE_zlib}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --with-zlib"; \
    fi; \
    if [ "${USE_zip}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --with-zip"; \
    fi; \
    if [ "${USE_bz2}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --with-bz2"; \
    fi; \
    # --- 网络与协议模块 ---
    if [ "${USE_curl}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --with-curl"; \
    fi; \
    if [ "${USE_ftp}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --enable-ftp"; \
    fi; \
    if [ "${USE_ldap}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --with-ldap"; \
    fi; \
    if [ "${USE_soap}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --enable-soap"; \
    fi; \
    if [ "${USE_sockets}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --enable-sockets"; \
    fi; \
    # --- 图像处理模块 ---
    if [ "${USE_gd}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --enable-gd --with-jpeg --with-freetype --with-webp --with-avif"; \
    fi; \
    if [ "${USE_exif}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --enable-exif"; \
    fi; \
    # --- 文本与国际化模块 ---
    if [ "${USE_mbstring}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --enable-mbstring"; \
    fi; \
    if [ "${USE_intl}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --enable-intl"; \
    fi; \
    if [ "${USE_gettext}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --with-gettext"; \
    fi; \
    if [ "${USE_xsl}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --with-xsl"; \
    fi; \
    if [ "${USE_tidy}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --with-tidy"; \
    fi; \
    # --- 数学模块 ---
    if [ "${USE_bcmath}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --enable-bcmath"; \
    fi; \
    if [ "${USE_gmp}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --with-gmp"; \
    fi; \
    # --- 系统与进程模块 ---
    if [ "${USE_pcntl}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --enable-pcntl"; \
    fi; \
    if [ "${USE_shmop}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --enable-shmop"; \
    fi; \
    if [ "${USE_sysvmsg}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --enable-sysvmsg"; \
    fi; \
    if [ "${USE_sysvsem}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --enable-sysvsem"; \
    fi; \
    if [ "${USE_sysvshm}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --enable-sysvshm"; \
    fi; \
    # --- 其他内置模块 ---
    if [ "${USE_calendar}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --enable-calendar"; \
    fi; \
    if [ "${USE_readline}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --with-readline"; \
    fi; \
    if [ "${USE_mhash}" = "true" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS --with-mhash"; \
    fi; \
    # PEAR/PECL 在 make install 后独立安装，避免 PEAR 安装程序在 QEMU 跨架构构建时挂起
    # --- OPcache ---
    # PHP 8.x OPcache 默认已编译（--enable-opcache 为默认值），运行时通过 zend_extension=opcache.so 加载
    # --- 自定义扩展参数 ---
    if [ -n "${EXTRA_PHP_EXTENSIONS}" ]; then \
      CONFIGURE_ARGS="$CONFIGURE_ARGS ${EXTRA_PHP_EXTENSIONS}"; \
    fi; \
    ./configure \
      --prefix=${PHP_DIR} \
      --with-config-file-path=${PHP_DIR}/etc \
      --with-config-file-scan-dir=${PHP_DIR}/etc/conf.d \
      --enable-fpm \
      --with-fpm-user=www-data \
      --with-fpm-group=www-data \
      $CONFIGURE_ARGS; \
    make -j$(nproc); \
    make install

# 手动安装 PEAR/PECL（独立于 make install，避免 QEMU 跨架构构建时挂起）
RUN set -eux; \
    if [ "${USE_pear}" = "true" ]; then \
      ${PHP_DIR}/bin/php -n \
        -d output_buffering=0 \
        -d open_basedir= \
        -d disable_functions= \
        -d "extension_dir=$(${PHP_DIR}/bin/php-config --extension-dir)" \
        ${PHP_SRC_DIR}/php/pear/install-pear-nozlib.phar \
        -d "${PHP_DIR}/lib/php" \
        -b "${PHP_DIR}/bin" \
        -p "${PHP_DIR}/bin/php"; \
    fi

# 安装 PECL 扩展（使用 (yes '' || true) 管道自动接受默认选项，避免交互式提示导致构建挂起；
# 外层 || true 防止 yes 收到 SIGPIPE 后退出码 141 在 pipefail 模式下导致构建失败）
# Redis 扩展 (从 Git 克隆最新稳定版，兼容 PHP 8.5)
RUN set -eux; \
    if [ "${USE_redis}" = "true" ]; then \
      cd ${PHP_SRC_DIR}; \
      if [ -n "${REDIS_VERSION}" ]; then \
        git clone --depth 1 -b "${REDIS_VERSION}" https://github.com/phpredis/phpredis.git \
          || { echo "ERROR: Failed to clone phpredis branch/tag '${REDIS_VERSION}'"; exit 1; }; \
      else \
        git clone --depth 1 https://github.com/phpredis/phpredis.git \
          || { echo "ERROR: Failed to clone phpredis repository"; exit 1; }; \
      fi; \
      cd phpredis; \
      ${PHP_DIR}/bin/phpize; \
      ./configure --with-php-config=${PHP_DIR}/bin/php-config; \
      make -j$(nproc); \
      make install; \
      # 清理源码，保证镜像体积最小化
      cd ${PHP_SRC_DIR} && rm -rf phpredis; \
    fi

# Memcached 扩展
RUN set -eux; \
    if [ "${USE_memcached}" = "true" ]; then \
      if [ -n "${MEMCACHED_VERSION}" ]; then \
        (yes '' || true) | ${PHP_DIR}/bin/pecl install "memcached-${MEMCACHED_VERSION}"; \
      else \
        (yes '' || true) | ${PHP_DIR}/bin/pecl install memcached; \
      fi; \
    fi

# ImageMagick 扩展 (保持目录整洁)
RUN set -eux; \
    if [ "${USE_imagick}" = "true" ]; then \
      cd ${PHP_SRC_DIR}; \
      if [ -n "${IMAGICK_VERSION}" ]; then \
        git clone --depth 1 -b "${IMAGICK_VERSION}" https://github.com/Imagick/imagick.git; \
      else \
        git clone --depth 1 https://github.com/Imagick/imagick.git; \
      fi; \
      cd imagick; \
      ${PHP_DIR}/bin/phpize; \
      ./configure --with-php-config=${PHP_DIR}/bin/php-config; \
      make -j$(nproc); \
      make install; \
      # 显式清理当前目录，虽然最后有统一清理，但养成习惯更好
      cd ${PHP_SRC_DIR} && rm -rf imagick; \
    fi

# MongoDB 扩展
RUN set -eux; \
    if [ "${USE_mongodb}" = "true" ]; then \
      if [ -n "${MONGODB_VERSION}" ]; then \
        (yes '' || true) | ${PHP_DIR}/bin/pecl install "mongodb-${MONGODB_VERSION}"; \
      else \
        (yes '' || true) | ${PHP_DIR}/bin/pecl install mongodb; \
      fi; \
    fi

# Swoole 扩展
RUN set -eux; \
    if [ "${USE_swoole}" = "true" ]; then \
      if [ -n "${SWOOLE_VERSION}" ]; then \
        (yes '' || true) | ${PHP_DIR}/bin/pecl install "swoole-${SWOOLE_VERSION}"; \
      else \
        (yes '' || true) | ${PHP_DIR}/bin/pecl install swoole; \
      fi; \
    fi

# Snuffleupagus 安全扩展（PHP 运行时安全加固）
RUN set -eux; \
    if [ "${USE_snuffleupagus}" = "true" ]; then \
      cd ${PHP_SRC_DIR}; \
      if [ -n "${SNUFFLEUPAGUS_VERSION}" ]; then \
        git clone --depth 1 -b "v${SNUFFLEUPAGUS_VERSION}" \
          https://github.com/jvoisin/snuffleupagus.git; \
      else \
        git clone --depth 1 https://github.com/jvoisin/snuffleupagus.git; \
      fi; \
      cd snuffleupagus/src; \
      ${PHP_DIR}/bin/phpize; \
      ./configure --with-php-config=${PHP_DIR}/bin/php-config; \
      make -j$(nproc); \
      make install; \
      # --- 修正：新增删除源码步骤 ---
      cd ${PHP_SRC_DIR}; \
      rm -rf snuffleupagus; \
    fi

# 清理源码目录以减小镜像体积
RUN rm -rf ${PHP_SRC_DIR}


# =======================================================
# Stage 2: 运行阶段 (Runtime Stage)
# CIS Docker Benchmark 合规 - 最小化镜像
# =======================================================
FROM debian:bookworm-slim

# hadolint ignore=DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# OCI 镜像标签（用于 Docker Hub 展示）
LABEL org.opencontainers.image.title="PHP-FPM" \
      org.opencontainers.image.description="Security-hardened PHP-FPM compiled from source, CIS Docker Benchmark compliant" \
      org.opencontainers.image.source="https://github.com/mzwrt/copilot" \
      org.opencontainers.image.licenses="MIT"

# 重新声明运行时需要的 ARGs
# 内置模块开关（用于条件安装运行时依赖）
ARG USE_mysql
ARG USE_pgsql
ARG USE_openssl
ARG USE_sodium
ARG USE_argon2
ARG USE_zlib
ARG USE_zip
ARG USE_bz2
ARG USE_curl
ARG USE_ftp
ARG USE_ldap
ARG USE_soap
ARG USE_sockets
ARG USE_gd
ARG USE_exif
ARG USE_mbstring
ARG USE_intl
ARG USE_gettext
ARG USE_xsl
ARG USE_tidy
ARG USE_bcmath
ARG USE_gmp
ARG USE_pcntl
ARG USE_shmop
ARG USE_sysvmsg
ARG USE_sysvsem
ARG USE_sysvshm
ARG USE_calendar
ARG USE_readline
ARG USE_mhash
ARG USE_pear
# 第三方扩展开关
ARG USE_redis
ARG USE_memcached
ARG USE_imagick
ARG USE_mongodb
ARG USE_swoole
ARG USE_opcache
ARG USE_snuffleupagus

ENV DEBIAN_FRONTEND=noninteractive \
    PHP_DIR=/opt/php \
    PATH="/opt/php/bin:/opt/php/sbin:${PATH}"

# CIS Docker 4.1 - 创建非 root 运行用户
RUN groupadd -r www-data 2>/dev/null || true \
    && useradd -r -g www-data -s /sbin/nologin -d /nonexistent www-data 2>/dev/null || true

# CIS Docker 4.3 - 仅安装必要的运行时依赖（根据模块开关按需安装，最小化攻击面）
RUN set -eux; \
    apt-get update; \
    # 基础依赖（始终安装：curl 为 CLI 工具，libcurl4 为 PHP curl 扩展运行时库）
    PKGS="ca-certificates libxml2 libsqlite3-0 curl libevent-2.1-7"; \
    # --- 根据模块开关条件添加依赖 ---
    if [ "${USE_openssl}" = "true" ]; then PKGS="$PKGS libssl3"; fi; \
    if [ "${USE_zlib}" = "true" ]; then PKGS="$PKGS zlib1g"; fi; \
    if [ "${USE_curl}" = "true" ]; then PKGS="$PKGS libcurl4"; fi; \
    if [ "${USE_gd}" = "true" ]; then PKGS="$PKGS libpng16-16 libjpeg62-turbo libfreetype6 libwebp7 libavif15"; fi; \
    if [ "${USE_mbstring}" = "true" ]; then PKGS="$PKGS libonig5"; fi; \
    if [ "${USE_zip}" = "true" ]; then PKGS="$PKGS libzip4"; fi; \
    if [ "${USE_sodium}" = "true" ]; then PKGS="$PKGS libsodium23"; fi; \
    if [ "${USE_argon2}" = "true" ]; then PKGS="$PKGS libargon2-1"; fi; \
    if [ "${USE_readline}" = "true" ]; then PKGS="$PKGS libreadline8"; fi; \
    if [ "${USE_xsl}" = "true" ]; then PKGS="$PKGS libxslt1.1"; fi; \
    if [ "${USE_bz2}" = "true" ]; then PKGS="$PKGS libbz2-1.0"; fi; \
    if [ "${USE_gmp}" = "true" ]; then PKGS="$PKGS libgmp10"; fi; \
    if [ "${USE_ldap}" = "true" ]; then PKGS="$PKGS libldap-2.5-0"; fi; \
    if [ "${USE_pgsql}" = "true" ]; then PKGS="$PKGS libpq5"; fi; \
    if [ "${USE_intl}" = "true" ]; then PKGS="$PKGS libicu72"; fi; \
    if [ "${USE_tidy}" = "true" ]; then PKGS="$PKGS libtidy5deb1"; fi; \
    # --- 第三方扩展运行时依赖 ---
    if [ "${USE_memcached}" = "true" ]; then PKGS="$PKGS libmemcached11"; fi; \
    if [ "${USE_imagick}" = "true" ]; then PKGS="$PKGS libmagickwand-6.q16-6"; fi; \
    apt-get install -y --no-install-recommends $PKGS; \
    rm -rf /var/lib/apt/lists/*; \
    apt-get clean

# 从编译阶段复制 PHP 安装文件
COPY --from=builder /opt/php /opt/php

# 创建目录结构
RUN mkdir -p \
    ${PHP_DIR}/etc/conf.d \
    ${PHP_DIR}/var/log \
    /www/wwwroot/html \
    /tmp/php-session \
    /tmp/php-upload

# ============================================================
# 复制本地配置文件
# ============================================================

# 复制 PHP 配置文件
COPY conf/php.ini ${PHP_DIR}/etc/php.ini
COPY conf/php-fpm.conf ${PHP_DIR}/etc/php-fpm.conf
COPY conf/www.conf ${PHP_DIR}/etc/php-fpm.d/www.conf

# 根据编译选项条件性启用扩展配置
RUN set -eux; \
    # PHP 8.x OPcache 为独立 Zend 扩展，需通过 zend_extension=opcache.so 加载
    if [ "${USE_opcache}" = "true" ]; then \
      echo "zend_extension=opcache.so" > ${PHP_DIR}/etc/conf.d/10-opcache.ini; \
      echo "opcache.enable=1" >> ${PHP_DIR}/etc/conf.d/10-opcache.ini; \
      echo "opcache.enable_cli=0" >> ${PHP_DIR}/etc/conf.d/10-opcache.ini; \
    else \
      echo "opcache.enable=0" > ${PHP_DIR}/etc/conf.d/10-opcache.ini; \
      echo "opcache.enable_cli=0" >> ${PHP_DIR}/etc/conf.d/10-opcache.ini; \
    fi; \
    if [ "${USE_redis}" = "true" ]; then \
      echo "extension=redis.so" > ${PHP_DIR}/etc/conf.d/20-redis.ini; \
    fi; \
    if [ "${USE_memcached}" = "true" ]; then \
      echo "extension=memcached.so" > ${PHP_DIR}/etc/conf.d/20-memcached.ini; \
    fi; \
    if [ "${USE_imagick}" = "true" ]; then \
      echo "extension=imagick.so" > ${PHP_DIR}/etc/conf.d/20-imagick.ini; \
    fi; \
    if [ "${USE_mongodb}" = "true" ]; then \
      echo "extension=mongodb.so" > ${PHP_DIR}/etc/conf.d/20-mongodb.ini; \
    fi; \
    if [ "${USE_swoole}" = "true" ]; then \
      echo "extension=swoole.so" > ${PHP_DIR}/etc/conf.d/20-swoole.ini; \
    fi; \
    if [ "${USE_snuffleupagus}" = "true" ]; then \
      echo "extension=snuffleupagus.so" > ${PHP_DIR}/etc/conf.d/30-snuffleupagus.ini; \
      echo "sp.configuration_file=${PHP_DIR}/etc/snuffleupagus.rules" >> ${PHP_DIR}/etc/conf.d/30-snuffleupagus.ini; \
    fi

# 复制 Snuffleupagus 安全规则配置（条件性使用）
COPY conf/snuffleupagus.rules ${PHP_DIR}/etc/snuffleupagus.rules

# 创建默认 PHP 测试页面（仅返回状态信息，不暴露 phpinfo - PCI DSS 合规）
RUN echo '<?php echo "OK"; ?>' > /www/wwwroot/html/index.php

# ============================================================
# 文件权限设置（CIS Docker Benchmark 合规）
# ============================================================
# 预创建日志文件并设置权限（PID 文件在运行时由 php-fpm 写入 /run tmpfs）
RUN touch ${PHP_DIR}/var/log/php-fpm.log \
    && touch ${PHP_DIR}/var/log/php_error.log \
    && touch ${PHP_DIR}/var/log/php-fpm-slow.log \
    && touch ${PHP_DIR}/var/log/www.access.log \
    && touch ${PHP_DIR}/var/log/php_mail.log \
    # 配置文件权限
    && find ${PHP_DIR}/etc -type d -exec chmod 700 {} \; \
    && find ${PHP_DIR}/etc -type f -exec chmod 600 {} \; \
    # 网站目录权限（CIS / PCI DSS Req.6 - Web 根目录只读，PHP worker 不可写入）
    # 目录属主 root，组 www-data，权限 750：www-data 可列目录/读文件，但不可创建/删除文件
    && chown root:www-data /www/wwwroot/html \
    && chmod 750 /www/wwwroot/html \
    && find /www/wwwroot -type f -exec chown root:www-data {} \; -exec chmod 640 {} \; \
    # 临时目录权限
    && chown -R www-data:www-data /tmp/php-session \
    && chown -R www-data:www-data /tmp/php-upload \
    && chmod 700 /tmp/php-session \
    && chmod 700 /tmp/php-upload \
    # PHP 目录属主（统一设置为 root:root）
    && chown -R root:root ${PHP_DIR} \
    # 日志目录：master(root) 和 worker(www-data) 均需写入，覆盖 chown -R 结果
    && chown root:www-data ${PHP_DIR}/var/log \
    && chmod 770 ${PHP_DIR}/var/log \
    && chmod 640 ${PHP_DIR}/var/log/php-fpm.log \
    # php_error.log / www.access.log / php_mail.log 由 www-data 工作进程写入
    && chown www-data:www-data ${PHP_DIR}/var/log/php_error.log \
    && chmod 640 ${PHP_DIR}/var/log/php_error.log \
    && chown www-data:www-data ${PHP_DIR}/var/log/www.access.log \
    && chmod 640 ${PHP_DIR}/var/log/www.access.log \
    && chown www-data:www-data ${PHP_DIR}/var/log/php_mail.log \
    && chmod 640 ${PHP_DIR}/var/log/php_mail.log \
    # slowlog 由 master(root) 进程写入
    && chmod 640 ${PHP_DIR}/var/log/php-fpm-slow.log

# CIS Docker 4.9 - 使用 COPY 而非 ADD
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 500 /docker-entrypoint.sh

# 创建健康检查脚本（在构建时创建，避免运行时写入只读文件系统）
# 使用 PID 文件 + kill -0 检查，无需 procps/pgrep 包
RUN printf '#!/bin/sh\n# CIS Docker 4.6 - 健康检查：通过 PID 文件验证 php-fpm master 存活\nPHP_FPM_PID=/run/php-fpm.pid\nif [ -s "$PHP_FPM_PID" ] && kill -0 "$(cat $PHP_FPM_PID)" 2>/dev/null; then\n  exit 0\nfi\nexit 1\n' \
    > /usr/local/bin/php-fpm-healthcheck \
    && chmod 555 /usr/local/bin/php-fpm-healthcheck

# CIS Docker 4.8 - 移除不必要的 setuid/setgid 权限
# 必须在所有 COPY 操作之后执行，确保从构建阶段复制的文件也被检查
RUN find / -perm /6000 -type f -exec chmod a-s {} \; 2>/dev/null || true

# CIS Docker 4.6 - 健康检查
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
    CMD php-fpm-healthcheck || exit 1

EXPOSE 36000

# 优雅停止信号
STOPSIGNAL SIGQUIT

ENTRYPOINT ["/docker-entrypoint.sh"]

# 前台运行 PHP-FPM（Docker 要求主进程在前台运行）
CMD ["/opt/php/sbin/php-fpm", "--nodaemonize"]
