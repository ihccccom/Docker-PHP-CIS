#!/usr/bin/env bash
# =====================================================================
# verify-snuffleupagus.sh —— 验证 snuffleupagus-wordpress.rules 的每条规则是否按说明生效
#
# 用法 1（推荐，直接测你构建好的镜像，不影响线上容器、不挂载线上卷）：
#   ./verify-snuffleupagus.sh docker  你的镜像名  ./snuffleupagus-wordpress.rules
#   例： ./verify-snuffleupagus.sh docker ihccccom/php-fpm:latest ./snuffleupagus-wordpress.rules
#
# 用法 2（本机已装 PHP + snuffleupagus.so 时）：
#   ./verify-snuffleupagus.sh local ./snuffleupagus-wordpress.rules /path/to/snuffleupagus.so
#
# 说明：
#   - 每个用例在一个全新的 PHP 进程里运行；"DROP"表示应当被规则拦截，"ALLOW"表示应当放行。
#   - 用 php -n（不读 php.ini），因此不受 disable_functions 影响，能单独测出规则本身。
#   - 用例编号 Rxx 与规则文件里的章节编号一一对应。
#   - R04（Secure）、R05（SameSite）需要看 HTTP 响应头，本脚本不覆盖，见规则文件内说明。
# 退出码：全部通过为 0，有失败为 1。
# =====================================================================
set -u
MODE="${1:-}"
if [ "$MODE" = "docker" ]; then
  IMAGE="${2:?缺少镜像名}"; RULES="${3:?缺少规则文件}"
elif [ "$MODE" = "local" ]; then
  RULES="${2:?缺少规则文件}"; SO="${3:?缺少 snuffleupagus.so 路径}"
else
  sed -n '2,20p' "$0"; exit 2
fi
[ -f "$RULES" ] || { echo "规则文件不存在: $RULES"; exit 2; }
RULES_ABS="$(cd "$(dirname "$RULES")" && pwd)/$(basename "$RULES")"
CASEDIR="$(mktemp -d)"; trap 'rm -rf "$CASEDIR"' EXIT
chmod 755 "$CASEDIR"

# 用例用到的辅助文件
echo '<?php echo "INC_OK";'              > "$CASEDIR/ok.php"
echo 'plain text'                        > "$CASEDIR/bad.txt"
echo '<?php $upgrading = time();'        > "$CASEDIR/.maintenance"
chmod 644 "$CASEDIR"/ok.php "$CASEDIR"/bad.txt "$CASEDIR"/.maintenance

# T = 用例里引用辅助文件的目录；W = 可写临时目录
if [ "$MODE" = "docker" ]; then T=/t; else T="$CASEDIR"; fi
W=/tmp

run_php() {   # $1 = case.php 在宿主机的路径
  if [ "$MODE" = "docker" ]; then
    docker run --rm -v "$RULES_ABS:/r/rules:ro" -v "$CASEDIR:/t:ro" --entrypoint php "$IMAGE" \
      -n -d extension=snuffleupagus.so -d sp.configuration_file=/r/rules -d sendmail_path=/bin/true /t/case.php 2>&1
  else
    local extdir exts=""
    extdir="$(php-config --extension-dir 2>/dev/null)"
    for e in xml dom curl mbstring; do [ -f "$extdir/$e.so" ] && exts="$exts -d extension=$extdir/$e.so"; done
    php -n $exts -d extension="$SO" -d sp.configuration_file="$RULES_ABS" -d sendmail_path=/bin/true "$1" 2>&1
  fi
}

declare -A RES_PASS RES_FAIL ORDER_SEEN
ORDER=(); PASS=0; FAIL=0
# t <规则编号> <ALLOW|DROP> <用例说明> <PHP 代码，可含 @T@ @W@>
t() {
  local id="$1" expect="$2" name="$3" code="$4" out got
  code="${code//@T@/$T}"; code="${code//@W@/$W}"
  printf '<?php\n%s\n' "$code" > "$CASEDIR/case.php"
  out="$(run_php "$CASEDIR/case.php")"
  if grep -q '\[drop\]' <<<"$out"; then got=DROP
  elif grep -qiE 'Fatal error|Parse error|Unexpected keyword' <<<"$out"; then got=ERROR
  else got=ALLOW; fi
  [ -z "${ORDER_SEEN[$id]:-}" ] && { ORDER+=("$id"); ORDER_SEEN[$id]=1; }
  if [ "$got" = "$expect" ]; then
    PASS=$((PASS+1)); RES_PASS[$id]=$(( ${RES_PASS[$id]:-0} + 1 )); printf '  通过  [%-5s] %-4s %s\n' "$expect" "$id" "$name"
  else
    FAIL=$((FAIL+1)); RES_FAIL[$id]=$(( ${RES_FAIL[$id]:-0} + 1 ))
    printf '  失败  期望 %-5s 实际 %-5s %-4s %s\n        输出: %s\n' "$expect" "$got" "$id" "$name" "$(head -c 260 <<<"$out" | tr '\n' ' ')"
  fi
}

echo "镜像/环境: $([ "$MODE" = docker ] && echo "docker $IMAGE" || echo "local $(php -v | head -1)")"
echo "规则文件 : $RULES_ABS"
echo

echo "--- 应放行：规则文件可加载；WordPress 正常行为不被误杀 ---"
t R01 ALLOW "规则文件可加载（无语法错误）"                  'echo "LOADED_OK";'
t R02 ALLOW "rand / mt_rand / random_int 正常返回"           'echo mt_rand(1,10), rand(1,10), random_int(1,5); echo " ";'
t R03 ALLOW "XML 解析正常（DOM loadXML）"                    '$d=new DOMDocument(); var_dump($d->loadXML("<a>1</a>"));'
t R06 ALLOW "读取 open_basedir（站点健康/更新器会读）"        'var_dump(ini_get("open_basedir"));'
t R07 ALLOW "其他 ini_set 不受影响（memory_limit，WP 每请求调用）" 'ini_set("memory_limit","256M"); echo "x";'
t R07 ALLOW "ini_set display_errors=0（WP 的 AJAX/REST 调用）"  'ini_set("display_errors",0); echo "x";'
t R07 ALLOW "ini_set error_log（WP_DEBUG_LOG 调用）"           'ini_set("error_log","@W@/sp-verify.log"); echo "x";'
t R08 ALLOW "system 无元字符命令"                            'system("echo hi");'
t R09 ALLOW "eval 普通代码"                                  'eval("echo 1+1;");'
t R10 ALLOW "putenv TZ=（不在拦截前缀内）"                   'putenv("TZ=UTC"); echo "x";'
t R11 ALLOW "mail 带 -f 安全发件人（PHPMailer 形式）"         '@mail("a@b.c","s","m","","-fuser@example.com"); echo "x";'
t R11 ALLOW "mail 无额外参数"                                '@mail("a@b.c","s","m"); echo "x";'
t R12 ALLOW "move_uploaded_file my.photo_.png（正常文件名）"  '@move_uploaded_file("@W@/none","@W@/my.photo_.png"); echo "x";'
t R12 ALLOW "move_uploaded_file report.phone.png"            '@move_uploaded_file("@W@/none","@W@/report.phone.png"); echo "x";'
t R13 ALLOW "chmod 0644"                                     'touch("@W@/sp-verify-c"); chmod("@W@/sp-verify-c",0644); echo "x";'
t R14 ALLOW "include .php"                                   'include "@T@/ok.php";'
t R14 ALLOW "require .maintenance（WP 维护模式）"             'require "@T@/.maintenance"; echo "x";'
t R15 ALLOW "curl_init https 地址"                           'if(!function_exists("curl_init")){echo "no-curl";}else{$c=curl_init("https://example.com/"); echo "x";}'
t R15 ALLOW "curl VERIFYPEER=0（WP-Cron 回环，核心默认）"     'if(!function_exists("curl_init")){echo "no-curl";}else{$c=curl_init(); curl_setopt($c, CURLOPT_SSL_VERIFYPEER, 0); curl_setopt($c, CURLOPT_SSL_VERIFYHOST, 0); echo "x";}'

echo
echo "--- 应拦截：攻击行为 ---"
t R06 DROP  "ini_set open_basedir"                           'ini_set("open_basedir","/"); echo "x";'
t R07 DROP  "ini_set zend.assertions"                        'ini_set("zend.assertions","1"); echo "x";'
t R07 DROP  "ini_set assert.active"                          'ini_set("assert.active","1"); echo "x";'
t R08 DROP  "system  命令注入 ;"                              'system("echo a; id");'
t R08 DROP  "system  命令注入 \$()"                           'system("echo \$(id)");'
t R08 DROP  "exec    命令注入 |"                              'exec("echo a | cat");'
t R08 DROP  "shell_exec 命令注入 反引号"                       'shell_exec("echo `id`");'
t R08 DROP  "passthru 命令注入 ;"                              'passthru("echo a; id");'
t R08 DROP  "popen   命令注入 &"                              'popen("echo a & id","r");'
t R08 DROP  "proc_open 命令注入 ;"                            '$p=proc_open("echo a; id", [1=>["pipe","w"]], $pipes);'
t R09 DROP  "eval 中调用 system"                              'eval("system(\"id\");");'
t R10 DROP  "putenv LD_PRELOAD"                              'putenv("LD_PRELOAD=@W@/x.so");'
t R10 DROP  "putenv PATH"                                    'putenv("PATH=@W@");'
t R10 DROP  "putenv GCONV_PATH"                              'putenv("GCONV_PATH=@W@");'
t R11 DROP  "mail -X 写文件"                                  '@mail("a@b.c","s","m","","-X/tmp/x.php"); echo "x";'
t R11 DROP  "mail -f 后拼接 -X"                               '@mail("a@b.c","s","m","","-fa@b.c -X/tmp/x.php"); echo "x";'
t R11 DROP  "mail -oQ 注入"                                   '@mail("a@b.c","s","m","","-oQ/tmp/"); echo "x";'
t R11 DROP  "mb_send_mail -X 写文件"                          'if(!function_exists("mb_send_mail")){echo "DROPPED-SKIP";}else{@mb_send_mail("a@b.c","s","m","","-X/tmp/x.php"); echo "x";}'
t R12 DROP  "move_uploaded_file x.php"                       '@move_uploaded_file("@W@/none","@W@/x.php"); echo "x";'
t R12 DROP  "move_uploaded_file x.php_.png（WP 改名后）"      '@move_uploaded_file("@W@/none","@W@/x.php_.png"); echo "x";'
t R12 DROP  "move_uploaded_file x.phtml"                     '@move_uploaded_file("@W@/none","@W@/x.phtml"); echo "x";'
t R12 DROP  "move_uploaded_file x.phar"                      '@move_uploaded_file("@W@/none","@W@/x.phar"); echo "x";'
t R12 DROP  "move_uploaded_file .htaccess"                   '@move_uploaded_file("@W@/none","@W@/.htaccess"); echo "x";'
t R12 DROP  "move_uploaded_file .user.ini"                   '@move_uploaded_file("@W@/none","@W@/.user.ini"); echo "x";'
t R13 DROP  "chmod 0777"                                     'touch("@W@/sp-verify-c"); chmod("@W@/sp-verify-c",0777);'
t R13 DROP  "chmod 0666"                                     'touch("@W@/sp-verify-c"); chmod("@W@/sp-verify-c",0666);'
t R14 DROP  "include http:// 远程包含"                        'include "http://127.0.0.1:1/x.php";'
t R14 DROP  "require https:// 远程包含"                       'require "https://127.0.0.1:1/x.php";'
t R14 DROP  "include_once ftp://"                            'include_once "ftp://127.0.0.1:1/x.php";'
t R14 DROP  "require_once data:// 伪协议"                     'require_once "data://text/plain;base64,PD9waHAgZWNobyAxOw==";'
t R14 DROP  "include php://input 伪协议"                      'include "php://input";'
t R14 DROP  "include phar:// 伪协议（以 .php 结尾也拦）"       'include "phar://@W@/a.phar/x.php";'
t R14 DROP  "include .txt"                                   'include "@T@/bad.txt";'
t R14 DROP  "include /etc/passwd（无后缀）"                   'include "/etc/passwd";'
t R15 DROP  "curl_init file://"                              'if(!function_exists("curl_init")){echo "DROPPED-SKIP";}else{$c=curl_init("file:///etc/passwd"); echo "x";}'
t R15 DROP  "curl_setopt URL=file://"                        'if(!function_exists("curl_init")){echo "DROPPED-SKIP";}else{$c=curl_init(); curl_setopt($c, CURLOPT_URL, "file:///etc/passwd"); echo "x";}'
t R15 DROP  "curl_setopt SSLENGINE(10089)"                   'if(!function_exists("curl_init")){echo "DROPPED-SKIP";}else{$c=curl_init(); curl_setopt($c, 10089, "x"); echo "x";}'

echo
echo "================ 按规则汇总 ================"
for id in "${ORDER[@]}"; do
  f="${RES_FAIL[$id]:-0}"; p="${RES_PASS[$id]:-0}"
  [ "$f" -eq 0 ] && printf '  %-4s 通过 (%s 项)\n' "$id" "$p" || printf '  %-4s 失败 (%s 项失败 / %s 项通过)\n' "$id" "$f" "$p"
done
echo "  R04/R05 需看响应头，见规则文件说明（脚本不覆盖）"
echo "============================================"
echo "总计：通过 $PASS 项，失败 $FAIL 项"
[ "$FAIL" -eq 0 ]
