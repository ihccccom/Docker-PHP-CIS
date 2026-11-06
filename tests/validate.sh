#!/usr/bin/env bash
# =======================================================
# PHP-FPM Docker 容器安全配置验证脚本
# 验证 CIS Docker Benchmark 合规性
# =======================================================
#
# 用法：
#   ./validate.sh [容器名称]
#
# 参数：
#   容器名称  - 要验证的 Docker 容器名称（默认: php）
#
# 示例：
#   ./validate.sh
#   ./validate.sh my-php
#

set -euo pipefail

# ============================================================
# 全局变量
# ============================================================

# 容器名称，默认为 "php"
CONTAINER_NAME="${1:-php}"

# PHP 安装目录
PHP_DIR="/opt/php"

# 测试计数器
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
INFO_COUNT=0
TOTAL_COUNT=0

# ============================================================
# 颜色定义
# ============================================================
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

# ============================================================
# 辅助函数
# ============================================================

pass() {
    ((TOTAL_COUNT++)) || true
    ((PASS_COUNT++)) || true
    echo -e "${GREEN}[PASS]${NC} $1"
}

fail() {
    ((TOTAL_COUNT++)) || true
    ((FAIL_COUNT++)) || true
    echo -e "${RED}[FAIL]${NC} $1"
}

skip() {
    ((TOTAL_COUNT++)) || true
    ((SKIP_COUNT++)) || true
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

info() {
    ((INFO_COUNT++)) || true
    echo -e "${BLUE}[INFO]${NC} $1"
}

docker_exec() {
    docker exec "${CONTAINER_NAME}" "$@" 2>/dev/null
}

get_inspect() {
    if [[ -z "${INSPECT_CACHE:-}" ]]; then
        INSPECT_CACHE=$(docker inspect "${CONTAINER_NAME}" 2>/dev/null) || INSPECT_CACHE=""
    fi
    echo "${INSPECT_CACHE}"
}

section() {
    echo ""
    echo -e "${BOLD}=== $1 ===${NC}"
    echo ""
}

# ============================================================
# 容器安全测试
# ============================================================
test_container() {
    section "容器安全测试 (Container Security Tests)"

    local inspect
    inspect=$(get_inspect)

    # 检查容器是否正在运行
    local state
    state=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['State']['Status'])" 2>/dev/null) || state=""
    if [[ "${state}" == "running" ]]; then
        pass "容器 '${CONTAINER_NAME}' 正在运行"
    else
        fail "容器 '${CONTAINER_NAME}' 未运行 (状态: ${state:-unknown})"
        info "后续测试可能会失败，请先启动容器"
        return
    fi

    # 检查容器是否以非特权模式运行 (CIS 5.4)
    local privileged
    privileged=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['Privileged'])" 2>/dev/null) || privileged=""
    if [[ "${privileged}" == "False" ]]; then
        pass "容器未以特权模式运行 (CIS 5.4)"
    else
        fail "容器以特权模式运行 (CIS 5.4)"
    fi

    # 检查 no-new-privileges 安全选项 (CIS 5.25)
    local security_opts
    security_opts=$(echo "${inspect}" | python3 -c "import sys,json; opts=json.load(sys.stdin)[0]['HostConfig']['SecurityOpt']; print(' '.join(opts) if opts else '')" 2>/dev/null) || security_opts=""
    if echo "${security_opts}" | grep -q "no-new-privileges"; then
        pass "已启用 no-new-privileges 安全选项 (CIS 5.25)"
    else
        fail "未启用 no-new-privileges 安全选项 (CIS 5.25)"
    fi

    # 检查 cap_drop ALL (CIS 5.3)
    local cap_drop
    cap_drop=$(echo "${inspect}" | python3 -c "import sys,json; caps=json.load(sys.stdin)[0]['HostConfig']['CapDrop']; print(' '.join(caps) if caps else '')" 2>/dev/null) || cap_drop=""
    if echo "${cap_drop}" | grep -qi "all"; then
        pass "已配置 cap_drop ALL (CIS 5.3)"
    else
        fail "未配置 cap_drop ALL (CIS 5.3)"
    fi

    # 检查内存限制 (CIS 5.10)
    local memory
    memory=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['Memory'])" 2>/dev/null) || memory="0"
    if [[ "${memory}" -gt 0 ]]; then
        local memory_mb=$((memory / 1024 / 1024))
        pass "已设置内存限制: ${memory_mb}MB (CIS 5.10)"
    else
        fail "未设置内存限制 (CIS 5.10)"
    fi

    # 检查 CPU 限制 (CIS 5.11)
    local nano_cpus cpu_period cpu_quota
    nano_cpus=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['NanoCpus'])" 2>/dev/null) || nano_cpus="0"
    cpu_period=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['CpuPeriod'])" 2>/dev/null) || cpu_period="0"
    cpu_quota=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['CpuQuota'])" 2>/dev/null) || cpu_quota="0"
    if [[ "${nano_cpus}" -gt 0 ]] || { [[ "${cpu_period}" -gt 0 ]] && [[ "${cpu_quota}" -gt 0 ]]; }; then
        pass "已设置 CPU 限制 (CIS 5.11)"
    else
        fail "未设置 CPU 限制 (CIS 5.11)"
    fi

    # 检查 PID 限制 (CIS 5.28)
    local pids_limit
    pids_limit=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['PidsLimit'])" 2>/dev/null) || pids_limit="0"
    if [[ "${pids_limit}" -gt 0 ]]; then
        pass "已设置 PID 限制: ${pids_limit} (CIS 5.28)"
    else
        fail "未设置 PID 限制 (CIS 5.28)"
    fi

    # 检查健康检查配置 (CIS 5.26)
    local healthcheck
    healthcheck=$(echo "${inspect}" | python3 -c "import sys,json; hc=json.load(sys.stdin)[0]['Config'].get('Healthcheck'); print(hc['Test'] if hc else '')" 2>/dev/null) || healthcheck=""
    if [[ -n "${healthcheck}" ]]; then
        pass "已配置健康检查 (CIS 5.26)"
    else
        fail "未配置健康检查 (CIS 5.26)"
    fi

    # 检查日志驱动配置
    local log_driver
    log_driver=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['LogConfig']['Type'])" 2>/dev/null) || log_driver=""
    if [[ -n "${log_driver}" ]]; then
        pass "已配置日志驱动: ${log_driver}"
    else
        fail "未配置日志驱动"
    fi
}

# ============================================================
# PHP-FPM 服务测试
# ============================================================
test_php_fpm() {
    section "PHP-FPM 服务测试 (PHP-FPM Service Tests)"

    # 检查 PHP-FPM 进程是否正在运行（通过 PID 文件验证，无需 pgrep/procps）
    local php_pid_file="/run/php-fpm.pid"
    local php_pid=""
    php_pid=$(docker_exec sh -c "cat ${php_pid_file} 2>/dev/null") || php_pid=""
    if [[ -n "${php_pid}" ]] && docker_exec kill -0 "${php_pid}" 2>/dev/null; then
        pass "PHP-FPM 进程正在运行 (PID: ${php_pid})"
    else
        fail "PHP-FPM 进程未运行"
        info "后续 PHP-FPM 测试将被跳过"
        return
    fi

    # 检查 PHP-FPM 是否在 36000 端口监听
    local port_listen
    port_listen=$(docker_exec sh -c "ss -tlnp 2>/dev/null | grep ':36000' || netstat -tlnp 2>/dev/null | grep ':36000'") || port_listen=""
    if [[ -n "${port_listen}" ]]; then
        pass "PHP-FPM 在端口 36000 正常监听"
    else
        # 尝试使用其他方式检查
        local fpm_conf_listen
        fpm_conf_listen=$(docker_exec grep -r "^listen" "${PHP_DIR}/etc/php-fpm.d/" 2>/dev/null) || fpm_conf_listen=""
        if [[ -n "${fpm_conf_listen}" ]]; then
            info "PHP-FPM 监听配置: ${fpm_conf_listen}"
        else
            fail "PHP-FPM 端口 36000 未监听"
        fi
    fi

    # 检查 PHP 版本信息
    local php_version
    php_version=$(docker_exec php -v 2>/dev/null | head -1) || php_version=""
    if [[ -n "${php_version}" ]]; then
        pass "PHP 版本: ${php_version}"
    else
        fail "无法获取 PHP 版本信息"
    fi

    # 检查 expose_php 是否关闭（安全）
    local expose_php
    expose_php=$(docker_exec php -i 2>/dev/null | grep "^expose_php" | awk '{print $NF}') || expose_php=""
    if [[ "${expose_php}" == "Off" ]]; then
        pass "expose_php 已关闭（安全）"
    elif [[ -n "${expose_php}" ]]; then
        fail "expose_php 未关闭: ${expose_php}"
    else
        skip "无法检查 expose_php 配置"
    fi

    # 检查 disable_functions 是否配置
    local disable_functions
    disable_functions=$(docker_exec php -i 2>/dev/null | grep "^disable_functions" | head -1) || disable_functions=""
    if [[ -n "${disable_functions}" ]] && [[ "${disable_functions}" != *"no value"* ]]; then
        pass "已配置 disable_functions 安全限制"
    else
        fail "未配置 disable_functions（安全风险）"
    fi

    # 检查 allow_url_include 是否关闭
    local allow_url_include
    allow_url_include=$(docker_exec php -i 2>/dev/null | grep "^allow_url_include" | awk '{print $NF}') || allow_url_include=""
    if [[ "${allow_url_include}" == "Off" ]]; then
        pass "allow_url_include 已关闭（安全）"
    elif [[ -n "${allow_url_include}" ]]; then
        fail "allow_url_include 未关闭: ${allow_url_include}"
    else
        skip "无法检查 allow_url_include 配置"
    fi

    # 检查 max_execution_time 是否符合 CIS PHP Benchmark 2.13（≤ 60s）
    local max_exec_time
    max_exec_time=$(docker_exec php -i 2>/dev/null | grep "^max_execution_time" | awk '{print $NF}') || max_exec_time=""
    if [[ -n "${max_exec_time}" ]]; then
        if [[ "${max_exec_time}" =~ ^[0-9]+$ ]] && [[ "${max_exec_time}" -le 60 ]]; then
            pass "max_execution_time 符合 CIS PHP Benchmark: ${max_exec_time}s (≤ 60s)"
        else
            fail "max_execution_time 超出 CIS 推荐值: ${max_exec_time}s (应 ≤ 60s)"
        fi
    else
        skip "无法检查 max_execution_time 配置"
    fi

    # 检查 session.cookie_samesite 是否为 Strict（PCI DSS 6.3 CSRF 防护）
    local cookie_samesite
    cookie_samesite=$(docker_exec php -i 2>/dev/null | grep "^session.cookie_samesite" | awk '{print $NF}') || cookie_samesite=""
    if [[ -z "${cookie_samesite}" ]]; then
        skip "无法检查 session.cookie_samesite 配置"
    elif [[ "${cookie_samesite}" == "Strict" ]]; then
        pass "session.cookie_samesite = Strict（PCI DSS 6.3 CSRF 防护）"
    else
        fail "session.cookie_samesite 未设为 Strict: ${cookie_samesite}（PCI DSS 6.3）"
    fi

    # 检查 OPcache 状态
    local opcache_enabled
    opcache_enabled=$(docker_exec php -i 2>/dev/null | grep "opcache.enable =>" | head -1 | awk '{print $NF}') || opcache_enabled=""
    if [[ "${opcache_enabled}" == "On" ]] || [[ "${opcache_enabled}" == "1" ]]; then
        pass "OPcache 已启用（性能优化）"
    elif [[ -n "${opcache_enabled}" ]]; then
        info "OPcache 未启用: ${opcache_enabled}"
    else
        info "OPcache 模块可能未安装"
    fi

    # 检查已加载的扩展
    local extensions
    extensions=$(docker_exec php -m 2>/dev/null) || extensions=""
    if [[ -n "${extensions}" ]]; then
        local ext_count
        ext_count=$(echo "${extensions}" | grep -v '^\[' | grep -v '^$' | wc -l)
        pass "已加载 ${ext_count} 个 PHP 扩展"
    else
        fail "无法获取 PHP 扩展列表"
    fi
}

# ============================================================
# PHP 安全设置测试（扩展）
# 覆盖三轮审查中所有已修复并经验证的 CIS / PCI DSS 配置项
# ============================================================
test_php_security_settings() {
    section "PHP 安全设置测试 (PHP Security Settings Tests)"

    # 缓存 php -i 输出（避免多次 fork，加速测试执行）
    local phpinfo
    phpinfo=$(docker_exec php -i 2>/dev/null) || phpinfo=""
    if [[ -z "${phpinfo}" ]]; then
        skip "无法获取 PHP 配置信息，跳过安全设置测试"
        return
    fi

    # 检查 display_errors 是否关闭（PCI DSS 6.5 / CIS - 防止错误信息泄露）
    local display_errors
    display_errors=$(echo "${phpinfo}" | grep "^display_errors" | awk '{print $NF}') || display_errors=""
    if [[ "${display_errors}" == "Off" ]]; then
        pass "display_errors 已关闭（PCI DSS 6.5 / CIS）"
    elif [[ -n "${display_errors}" ]]; then
        fail "display_errors 未关闭: ${display_errors}（PCI DSS 6.5 / CIS）"
    else
        skip "无法检查 display_errors 配置"
    fi

    # 检查 allow_url_fopen 是否关闭（CIS PHP Benchmark 2.3 - 防止远程文件包含攻击）
    local allow_url_fopen
    allow_url_fopen=$(echo "${phpinfo}" | grep "^allow_url_fopen" | awk '{print $NF}') || allow_url_fopen=""
    if [[ "${allow_url_fopen}" == "Off" ]]; then
        pass "allow_url_fopen 已关闭（CIS PHP Benchmark 2.3）"
    elif [[ -n "${allow_url_fopen}" ]]; then
        fail "allow_url_fopen 未关闭: ${allow_url_fopen}（CIS PHP Benchmark 2.3）"
    else
        skip "无法检查 allow_url_fopen 配置"
    fi

    # 检查 open_basedir 是否设置（CIS PHP Benchmark 2.2 - 防止路径遍历攻击）
    local open_basedir
    open_basedir=$(echo "${phpinfo}" | grep "^open_basedir" | awk '{print $NF}') || open_basedir=""
    if [[ -n "${open_basedir}" ]] && [[ "${open_basedir}" != "no value" ]]; then
        pass "open_basedir 已设置（CIS PHP Benchmark 2.2）: ${open_basedir}"
    else
        fail "open_basedir 未设置（CIS PHP Benchmark 2.2 - 防止路径遍历）"
    fi

    # 检查 cgi.fix_pathinfo 是否关闭（CIS PHP Benchmark 2.12 - 防止路径解析漏洞）
    local cgi_fix_pathinfo
    cgi_fix_pathinfo=$(echo "${phpinfo}" | grep "^cgi.fix_pathinfo" | awk '{print $NF}') || cgi_fix_pathinfo=""
    if [[ "${cgi_fix_pathinfo}" == "0" ]]; then
        pass "cgi.fix_pathinfo = 0（CIS PHP Benchmark 2.12）"
    elif [[ -n "${cgi_fix_pathinfo}" ]]; then
        fail "cgi.fix_pathinfo 未关闭: ${cgi_fix_pathinfo}（CIS PHP Benchmark 2.12）"
    else
        skip "无法检查 cgi.fix_pathinfo 配置"
    fi

    # 检查 max_input_vars 是否符合 CIS PHP Benchmark 2.18（≤ 1000 - 防哈希碰撞 DoS）
    local max_input_vars
    max_input_vars=$(echo "${phpinfo}" | grep "^max_input_vars" | awk '{print $NF}') || max_input_vars=""
    if [[ -n "${max_input_vars}" ]]; then
        if [[ "${max_input_vars}" =~ ^[0-9]+$ ]] && [[ "${max_input_vars}" -le 1000 ]]; then
            pass "max_input_vars 符合 CIS PHP Benchmark 2.18: ${max_input_vars} (≤ 1000)"
        else
            fail "max_input_vars 超出 CIS 推荐值: ${max_input_vars}（应 ≤ 1000，CIS PHP Benchmark 2.18）"
        fi
    else
        skip "无法检查 max_input_vars 配置"
    fi

    # 检查 unserialize_max_depth（CIS PHP Benchmark 2.5 - ≤ 200 防堆栈溢出 DoS）
    local unserialize_max_depth
    unserialize_max_depth=$(echo "${phpinfo}" | grep "^unserialize_max_depth" | awk '{print $NF}') || unserialize_max_depth=""
    if [[ -n "${unserialize_max_depth}" ]]; then
        if [[ "${unserialize_max_depth}" =~ ^[0-9]+$ ]] && [[ "${unserialize_max_depth}" -le 200 ]]; then
            pass "unserialize_max_depth 符合 CIS PHP Benchmark 2.5: ${unserialize_max_depth} (≤ 200)"
        else
            fail "unserialize_max_depth 超出 CIS 推荐值: ${unserialize_max_depth}（应 ≤ 200，CIS PHP Benchmark 2.5）"
        fi
    else
        skip "无法检查 unserialize_max_depth 配置"
    fi

    # 检查 report_memleaks 是否关闭（CIS PHP Benchmark Production Value - 防止内存泄漏信息写入错误日志）
    local report_memleaks
    report_memleaks=$(echo "${phpinfo}" | grep "^report_memleaks" | awk '{print $NF}') || report_memleaks=""
    if [[ "${report_memleaks}" == "Off" ]] || [[ "${report_memleaks}" == "0" ]]; then
        pass "report_memleaks 已关闭（防止内存信息泄露）"
    elif [[ -n "${report_memleaks}" ]]; then
        fail "report_memleaks 未关闭: ${report_memleaks}（可能将内存信息写入日志）"
    else
        skip "无法检查 report_memleaks 配置"
    fi

    # 检查 session.use_strict_mode（CIS PHP Benchmark 3.1 - 防止 Session ID 固定攻击）
    local session_strict_mode
    session_strict_mode=$(echo "${phpinfo}" | grep "^session.use_strict_mode" | awk '{print $NF}') || session_strict_mode=""
    if [[ "${session_strict_mode}" == "1" ]] || [[ "${session_strict_mode}" == "On" ]]; then
        pass "session.use_strict_mode 已启用（CIS PHP Benchmark 3.1）"
    elif [[ -n "${session_strict_mode}" ]]; then
        fail "session.use_strict_mode 未启用: ${session_strict_mode}（CIS PHP Benchmark 3.1）"
    else
        skip "无法检查 session.use_strict_mode 配置"
    fi

    # 检查 session.use_only_cookies（PCI DSS 6.3 - 防止 Session ID 在 URL 中泄露）
    local session_only_cookies
    session_only_cookies=$(echo "${phpinfo}" | grep "^session.use_only_cookies" | awk '{print $NF}') || session_only_cookies=""
    if [[ "${session_only_cookies}" == "1" ]] || [[ "${session_only_cookies}" == "On" ]]; then
        pass "session.use_only_cookies 已启用（PCI DSS 6.3）"
    elif [[ -n "${session_only_cookies}" ]]; then
        fail "session.use_only_cookies 未启用: ${session_only_cookies}（PCI DSS 6.3）"
    else
        skip "无法检查 session.use_only_cookies 配置"
    fi

    # 检查 session.cookie_secure（PCI DSS - 强制 Cookie 只通过 HTTPS 传输）
    local session_cookie_secure
    session_cookie_secure=$(echo "${phpinfo}" | grep "^session.cookie_secure" | awk '{print $NF}') || session_cookie_secure=""
    if [[ "${session_cookie_secure}" == "1" ]] || [[ "${session_cookie_secure}" == "On" ]]; then
        pass "session.cookie_secure 已启用（PCI DSS）"
    elif [[ -n "${session_cookie_secure}" ]]; then
        fail "session.cookie_secure 未启用: ${session_cookie_secure}（PCI DSS）"
    else
        skip "无法检查 session.cookie_secure 配置"
    fi

    # 检查 session.cookie_httponly（PCI DSS 6.5.4 - 防止 XSS 窃取 Session Cookie）
    local session_cookie_httponly
    session_cookie_httponly=$(echo "${phpinfo}" | grep "^session.cookie_httponly" | awk '{print $NF}') || session_cookie_httponly=""
    if [[ "${session_cookie_httponly}" == "1" ]] || [[ "${session_cookie_httponly}" == "On" ]]; then
        pass "session.cookie_httponly 已启用（PCI DSS 6.5.4）"
    elif [[ -n "${session_cookie_httponly}" ]]; then
        fail "session.cookie_httponly 未启用: ${session_cookie_httponly}（PCI DSS 6.5.4）"
    else
        skip "无法检查 session.cookie_httponly 配置"
    fi

    # 检查 session.serialize_handler 是否为 php_serialize（CIS PHP Benchmark 3.6 - 防止管道符 Session 注入漏洞）
    local session_serializer
    session_serializer=$(echo "${phpinfo}" | grep "^session.serialize_handler" | awk '{print $NF}') || session_serializer=""
    if [[ "${session_serializer}" == "php_serialize" ]]; then
        pass "session.serialize_handler = php_serialize（防止管道符 Session 注入漏洞）"
    elif [[ -n "${session_serializer}" ]]; then
        fail "session.serialize_handler 应为 php_serialize，当前值: ${session_serializer}"
    else
        skip "无法检查 session.serialize_handler 配置"
    fi

    # 检查 mysqlnd.collect_statistics 是否关闭（CIS PHP Benchmark 7.3 - 防止统计信息泄露）
    local mysqlnd_stats
    mysqlnd_stats=$(echo "${phpinfo}" | grep "^mysqlnd.collect_statistics" | awk '{print $NF}') || mysqlnd_stats=""
    if [[ "${mysqlnd_stats}" == "Off" ]] || [[ "${mysqlnd_stats}" == "0" ]]; then
        pass "mysqlnd.collect_statistics 已关闭（CIS PHP Benchmark 7.3）"
    elif [[ -n "${mysqlnd_stats}" ]]; then
        fail "mysqlnd.collect_statistics 未关闭: ${mysqlnd_stats}（CIS PHP Benchmark 7.3）"
    else
        skip "无法检查 mysqlnd.collect_statistics 配置（可能未启用 mysqlnd）"
    fi

    # 检查 soap.wsdl_cache_enabled 是否关闭（PCI DSS 6.5.8 - 防止 WSDL 缓存被投毒攻击）
    local wsdl_cache
    wsdl_cache=$(echo "${phpinfo}" | grep "^soap.wsdl_cache_enabled" | awk '{print $NF}') || wsdl_cache=""
    if [[ "${wsdl_cache}" == "0" ]] || [[ "${wsdl_cache}" == "Off" ]]; then
        pass "soap.wsdl_cache_enabled 已关闭（防止 WSDL 缓存投毒攻击）"
    elif [[ -n "${wsdl_cache}" ]]; then
        fail "soap.wsdl_cache_enabled 未关闭: ${wsdl_cache}（防止 WSDL 缓存投毒攻击）"
    else
        skip "无法检查 soap.wsdl_cache_enabled 配置（可能未启用 SOAP 模块）"
    fi

    # 检查 session.upload_progress.enabled 是否关闭（CIS PHP Benchmark 3.5 - 防止 Session 注入）
    local upload_progress
    upload_progress=$(echo "${phpinfo}" | grep "^session.upload_progress.enabled" | awk '{print $NF}') || upload_progress=""
    if [[ "${upload_progress}" == "Off" ]] || [[ "${upload_progress}" == "0" ]]; then
        pass "session.upload_progress.enabled 已关闭（CIS PHP Benchmark 3.5 - 防止 Session 注入）"
    elif [[ -n "${upload_progress}" ]]; then
        fail "session.upload_progress.enabled 未关闭: ${upload_progress}（CIS PHP Benchmark 3.5）"
    else
        skip "无法检查 session.upload_progress.enabled 配置"
    fi

    # 检查 max_multipart_body_parts 是否符合 CIS PHP Benchmark 2.25（≤ 250 防 DoS）
    local multipart_parts
    multipart_parts=$(echo "${phpinfo}" | grep "^max_multipart_body_parts" | awk '{print $NF}') || multipart_parts=""
    if [[ -n "${multipart_parts}" ]]; then
        if [[ "${multipart_parts}" =~ ^[0-9]+$ ]] && [[ "${multipart_parts}" -le 250 ]]; then
            pass "max_multipart_body_parts 符合 CIS PHP Benchmark 2.25: ${multipart_parts} (≤ 250)"
        else
            fail "max_multipart_body_parts 超出 CIS 推荐值: ${multipart_parts}（应 ≤ 250，CIS PHP Benchmark 2.25）"
        fi
    else
        skip "无法检查 max_multipart_body_parts 配置（可能为 PHP < 8.1）"
    fi

    # 检查 pcre.recursion_limit 是否符合 CIS PHP Benchmark 2.22（≤ 1000 防栈溢出）
    local pcre_recursion
    pcre_recursion=$(echo "${phpinfo}" | grep "^pcre.recursion_limit" | awk '{print $NF}') || pcre_recursion=""
    if [[ -n "${pcre_recursion}" ]]; then
        if [[ "${pcre_recursion}" =~ ^[0-9]+$ ]] && [[ "${pcre_recursion}" -le 1000 ]]; then
            pass "pcre.recursion_limit 符合 CIS PHP Benchmark 2.22: ${pcre_recursion} (≤ 1000)"
        else
            fail "pcre.recursion_limit 超出 CIS 推荐值: ${pcre_recursion}（应 ≤ 1000，CIS PHP Benchmark 2.22）"
        fi
    else
        skip "无法检查 pcre.recursion_limit 配置"
    fi

    # 检查 opcache.validate_root 是否启用（CIS - 防止符号链接目录穿越）
    local opcache_validate_root
    opcache_validate_root=$(echo "${phpinfo}" | grep "^opcache.validate_root" | awk '{print $NF}') || opcache_validate_root=""
    if [[ "${opcache_validate_root}" == "On" ]] || [[ "${opcache_validate_root}" == "1" ]]; then
        pass "opcache.validate_root 已启用（CIS - 防止符号链接目录穿越攻击）"
    elif [[ -n "${opcache_validate_root}" ]]; then
        fail "opcache.validate_root 未启用: ${opcache_validate_root}（CIS - 应设为 1）"
    else
        skip "无法检查 opcache.validate_root 配置（可能未启用 OPcache）"
    fi

    # 检查 opcache.restrict_api 是否设置（CIS - 防止 OPcache API 被不受信任脚本滥用）
    local opcache_restrict_api
    opcache_restrict_api=$(echo "${phpinfo}" | grep "^opcache.restrict_api" | sed 's/.*=> //' | awk '{print $1}') || opcache_restrict_api=""
    if [[ -n "${opcache_restrict_api}" ]] && [[ "${opcache_restrict_api}" != "no value" ]]; then
        pass "opcache.restrict_api 已设置（CIS - 防止 OPcache API 被任意脚本调用）: ${opcache_restrict_api}"
    elif echo "${phpinfo}" | grep -q "^opcache.restrict_api"; then
        fail "opcache.restrict_api 未设置（CIS - 任意脚本可调用 opcache_reset() 等 API）"
    else
        skip "无法检查 opcache.restrict_api 配置（可能未启用 OPcache）"
    fi

    # 检查 mail.log 是否设置（PCI DSS Req.10 - 审计所有 PHP mail() 调用）
    local mail_log
    mail_log=$(echo "${phpinfo}" | grep "^mail.log" | awk '{print $NF}') || mail_log=""
    if [[ -n "${mail_log}" ]] && [[ "${mail_log}" != "no value" ]]; then
        pass "mail.log 已配置（PCI DSS Req.10 - 审计 mail() 调用）: ${mail_log}"
    elif echo "${phpinfo}" | grep -q "^mail.log"; then
        fail "mail.log 未配置（PCI DSS Req.10 - 应记录所有 mail() 调用）"
    else
        skip "无法检查 mail.log 配置"
    fi

    # 检查 default_socket_timeout 是否符合资源保护要求（≤ 30s）
    # 过长的套接字超时会导致大量慢速连接耗尽 PHP-FPM Worker，形成资源耗尽攻击
    local socket_timeout
    socket_timeout=$(echo "${phpinfo}" | grep "^default_socket_timeout" | awk '{print $NF}')
    socket_timeout=${socket_timeout:-""}
    if [[ -n "${socket_timeout}" ]]; then
        if [[ "${socket_timeout}" =~ ^[0-9]+$ ]] && [[ "${socket_timeout}" -le 30 ]]; then
            pass "default_socket_timeout 符合资源保护要求: ${socket_timeout}s (≤ 30s)"
        else
            fail "default_socket_timeout 过长: ${socket_timeout}s（应 ≤ 30s，防止 Worker 资源耗尽）"
        fi
    else
        skip "无法检查 default_socket_timeout 配置"
    fi
}

# ============================================================
# 文件权限测试
# ============================================================
test_file_permissions() {
    section "文件权限测试 (File Permission Tests)"

    # 检查配置文件是否不可被其他用户读取
    local conf_world_readable
    conf_world_readable=$(docker_exec find "${PHP_DIR}/etc" -type f -perm -o=r 2>/dev/null) || conf_world_readable=""
    if [[ -z "${conf_world_readable}" ]]; then
        pass "配置文件不可被其他用户读取 (CIS)"
    else
        local count
        count=$(echo "${conf_world_readable}" | wc -l)
        fail "发现 ${count} 个配置文件可被其他用户读取 (CIS)"
    fi

    # 检查日志目录权限（CIS: other 位必须为 0，即不允许非属主/非属组访问）
    local log_dir_perms
    log_dir_perms=$(docker_exec stat -c '%a' "${PHP_DIR}/var/log" 2>/dev/null) || log_dir_perms=""
    if [[ -n "${log_dir_perms}" ]]; then
        # 检查 other 权限位（最低位）是否为 0（binary xxx xxx 000）
        # 且总权限不超过 770（所有者和组最多 rwx，other 为空）
        if [[ $(( 8#${log_dir_perms} & 7 )) -eq 0 ]] && [[ $((8#${log_dir_perms})) -le $((8#770)) ]]; then
            pass "日志目录权限正确（other位为0，不超过770）: ${log_dir_perms}"
        else
            fail "日志目录权限不符合要求（应 ≤770 且 other 位为0）: ${log_dir_perms}"
        fi
    else
        skip "日志目录不存在，跳过权限检查"
    fi

    # 检查 session 目录权限
    local session_dir_perms
    session_dir_perms=$(docker_exec stat -c '%a' "/tmp/php-session" 2>/dev/null) || session_dir_perms=""
    if [[ -n "${session_dir_perms}" ]]; then
        if [[ $((8#${session_dir_perms})) -le $((8#700)) ]]; then
            pass "Session 目录权限正确: ${session_dir_perms}"
        else
            fail "Session 目录权限过宽: ${session_dir_perms}，应为 700 或更严格"
        fi
    else
        skip "Session 目录不存在，跳过权限检查"
    fi

    # 检查网站根目录不应被 PHP worker(www-data) 写入（CIS / PCI DSS Req.6）
    # 以 www-data 身份测试写权限（-w）；docker exec 默认以 root 运行，需显式指定用户
    local webroot_write
    webroot_write=$(docker exec "${CONTAINER_NAME}" sh -c \
        'su -s /bin/sh www-data -c "test -w /www/wwwroot/html && echo writable || echo readonly"' \
        2>/dev/null) || webroot_write=""
    if [[ "${webroot_write}" == "readonly" ]]; then
        pass "网站根目录不可被 PHP worker(www-data) 写入（CIS / PCI DSS Req.6）"
    elif [[ "${webroot_write}" == "writable" ]]; then
        fail "网站根目录可被 PHP worker(www-data) 写入（CIS / PCI DSS Req.6 - PHP 不应能修改 Web 根目录）"
    else
        skip "无法检查网站根目录写权限（su 命令不可用或目录不存在）"
    fi

    # 检查 php-fpm.conf log_level 是否为 notice 或更详细（PCI DSS Req.10.2 - 进程生命周期审计）
    local fpm_log_level
    fpm_log_level=$(docker_exec grep -E "^log_level\s*=" "${PHP_DIR}/etc/php-fpm.conf" 2>/dev/null | awk -F'=' '{print $2}' | tr -d ' ')
    fpm_log_level=${fpm_log_level:-""}
    if [[ -z "${fpm_log_level}" ]]; then
        skip "无法读取 php-fpm.conf log_level 配置"
    else
        case "${fpm_log_level}" in
            notice|debug)
                pass "php-fpm.conf log_level 符合 PCI DSS Req.10.2: ${fpm_log_level}（捕获进程生命周期事件）"
                ;;
            *)
                fail "php-fpm.conf log_level 过于粗略: ${fpm_log_level}（应为 notice，PCI DSS Req.10.2 要求记录进程启停事件）"
                ;;
        esac
    fi
}

# ============================================================
# 打印测试摘要
# ============================================================
print_summary() {
    section "测试摘要 (Test Summary)"

    echo -e "  容器名称:  ${BOLD}${CONTAINER_NAME}${NC}"
    echo -e "  测试总数:  ${BOLD}${TOTAL_COUNT}${NC}"
    echo -e "  ${GREEN}通过: ${PASS_COUNT}${NC}"
    echo -e "  ${RED}失败: ${FAIL_COUNT}${NC}"
    echo -e "  ${YELLOW}跳过: ${SKIP_COUNT}${NC}"
    echo -e "  ${BLUE}提示: ${INFO_COUNT}${NC}"
    echo ""

    if [[ ${FAIL_COUNT} -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}所有测试通过！容器安全配置符合要求。${NC}"
    else
        echo -e "${RED}${BOLD}存在 ${FAIL_COUNT} 项测试失败，请检查并修复安全配置。${NC}"
    fi
    echo ""
}

# ============================================================
# 主函数
# ============================================================
main() {
    echo ""
    echo -e "${BOLD}PHP-FPM Docker 容器安全配置验证${NC}"
    echo -e "目标容器: ${BOLD}${CONTAINER_NAME}${NC}"
    echo -e "验证时间: $(date '+%Y-%m-%d %H:%M:%S')"

    # 预检查：确认 Docker 和 python3 是否可用
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}错误: docker 命令不可用，请先安装 Docker${NC}"
        exit 1
    fi
    if ! command -v python3 &>/dev/null; then
        echo -e "${RED}错误: python3 命令不可用，请先安装 Python 3${NC}"
        exit 1
    fi

    # 预检查：确认容器是否存在
    if ! docker inspect "${CONTAINER_NAME}" &>/dev/null; then
        echo -e "${RED}错误: 容器 '${CONTAINER_NAME}' 不存在${NC}"
        echo -e "用法: $0 [容器名称]"
        exit 1
    fi

    # 执行各类测试
    test_container
    test_php_fpm
    test_php_security_settings
    test_file_permissions

    # 打印测试摘要
    print_summary

    # 返回状态码：有失败则返回 1
    if [[ ${FAIL_COUNT} -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

# 运行主函数
main
