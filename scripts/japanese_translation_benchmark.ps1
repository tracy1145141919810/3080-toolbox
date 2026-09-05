param([Parameter(Mandatory=$true)][string]$Runtime,
 [Parameter(Mandatory=$true)][string]$Model,
 [Parameter(Mandatory=$true)][string]$OcrReport,
 [Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference = 'Stop'
$port = 18751
$key = [guid]::NewGuid().ToString('N')
$argsList = @('-m',('"'+$Model+'"'),'--host','127.0.0.1','--port',"$port",'--api-key',$key,'-ngl','99','-c','4096','-np','1','--jinja','--no-webui','--offline','--reasoning-budget','0','--cache-ram','0')
$server = Start-Process (Join-Path $Runtime 'llama-server.exe') -ArgumentList $argsList -WindowStyle Hidden -PassThru -RedirectStandardError "$Output.stderr.log" -RedirectStandardOutput "$Output.stdout.log"
$clock = [Diagnostics.Stopwatch]::StartNew()
$headers = @{Authorization="Bearer $key"}
try {
 do {
  try { $health=Invoke-RestMethod "http://127.0.0.1:$port/health" -Headers $headers -TimeoutSec 2; if($health.status -eq 'ok'){break} } catch {}
  if($server.HasExited -or $clock.Elapsed.TotalSeconds -gt 90){throw 'Model did not start'}
  Start-Sleep -Milliseconds 150
 } while($true)
 $loadMs=$clock.ElapsedMilliseconds
 $source=(Get-Content -LiteralPath $OcrReport -Raw | ConvertFrom-Json).blocks
 $results=foreach($block in $source){
  $body=@{messages=@(
   @{role='system';content='你是专业的日语到简体中文翻译。只输出当前原文的完整中文译文，不解释，不添加内容。人名、地名及片假名专有名词使用中文音译，不要把音节当作普通词逐字意译。已经是汉字的人名保留姓名并转为简体。最终结果不得残留日文平假名或片假名。即使没有常见译名，也必须用中文音译，不能照抄日文。'},
   @{role='user';content=$block.text}
  );temperature=0;max_tokens=256;stream=$false;chat_template_kwargs=@{enable_thinking=$false}}
  $clock.Restart()
  $response=Invoke-RestMethod "http://127.0.0.1:$port/v1/chat/completions" -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes(($body|ConvertTo-Json -Depth 8))) -TimeoutSec 60
  $translated=$response.choices[0].message.content.Trim()
  [pscustomobject]@{source=$block.text;translation=$translated;ms=$clock.ElapsedMilliseconds;kana=($translated -match '[\u3040-\u30FA\u30FD-\u30FF\uFF66-\uFF9D]')}
 }
 @{model=$Model;loadMs=$loadMs;results=@($results)} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Output -Encoding utf8
 $results | Format-Table -AutoSize
} finally {if(!$server.HasExited){Stop-Process -Id $server.Id}}
