# 스레드 자동 발행
# 글.txt 에 "발행: 2026-12-03 10:00" 이 있고, 그 시간이 지났고, 아직 발행완료.txt 가 없는 게시물을 스레드에 올립니다.
# 환경변수:
#   THREADS_TOKEN  스레드 장기 토큰 (GitHub Secrets 에 저장)
#   RAW_BASE       카드 이미지 공개 주소의 앞부분 (예: https://raw.githubusercontent.com/계정/저장소/커밋)
# 사용: pwsh -File cardnews/publish.ps1 [-DryRun]
param([switch]$DryRun)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common.ps1')

$Api = 'https://graph.threads.com/v1.0'
$token = $env:THREADS_TOKEN
$rawBase = ($env:RAW_BASE -replace '/+$', '')
$repoRoot = Split-Path -Parent $PSScriptRoot
$now = [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(9))

if (-not $DryRun -and -not $token) { Write-Output '[건너뜀] THREADS_TOKEN 이 없어 발행하지 않습니다.'; exit 0 }
if (-not $rawBase) { Write-Output '[오류] RAW_BASE 가 비어 있습니다.'; exit 1 }

function Api-Post([string]$path, [hashtable]$body) {
  $body['access_token'] = $token
  Invoke-RestMethod -Method Post -Uri "$Api/$path" -Body $body -ContentType 'application/x-www-form-urlencoded; charset=utf-8'
}
function Api-Get([string]$path, [string]$fields) {
  Invoke-RestMethod -Method Get -Uri ("$Api/$path" + "?fields=$fields&access_token=" + [Uri]::EscapeDataString($token))
}
function Wait-Ready([string]$id) {
  for ($t = 0; $t -lt 20; $t++) {
    $s = Api-Get $id 'status,error_message'
    if ($s.status -eq 'FINISHED') { return }
    if ($s.status -in 'ERROR', 'EXPIRED') { throw "컨테이너 $id 실패: $($s.status) $($s.error_message)" }
    Start-Sleep -Seconds 6
  }
  throw "컨테이너 $id 준비 시간 초과"
}
function To-PublicUrl([string]$fullPath) {
  $rel = $fullPath.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
  $encoded = (($rel -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
  "$rawBase/$encoded"
}

$published = 0
foreach ($f in (Get-ChildItem $PostsDir -Directory | Sort-Object Name)) {
  $p = Read-Post $f.FullName
  if (-not $p -or -not $p.Head.publish) { continue }
  $done = Join-Path $f.FullName $DoneFileName
  if (Test-Path $done) { continue }
  $when = Parse-KstTime $p.Head.publish
  if (-not $when) { Write-Output "[주의] $($f.Name): 발행 시간 형식이 틀림"; continue }
  if ($when -gt $now) { Write-Output "[대기] $($f.Name): $($when.ToString('yyyy-MM-dd HH:mm')) 발행 예정"; continue }

  $cards = @(Get-ChildItem (Join-Path $f.FullName $CardsDirName) -Filter *.png -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 20)
  if (-not $cards.Count) { Write-Output "[주의] $($f.Name): 카드뉴스가 아직 없음"; continue }
  $text = ([string]$p.Head.body).TrimEnd()
  # 링크: 기본은 랜딩페이지. 글.txt 에 "링크: 없음" 이면 안 붙이고, "링크: 주소" 면 그 주소를 붙임
  $link = if ($p.Head.link) { $p.Head.link.Trim() } else { $SiteUrl }
  if ($link -and $link -ne '없음' -and -not $text.Contains($link)) { $text = "$text`n`n🍊 $link" }
  $urls = @($cards | ForEach-Object { To-PublicUrl $_.FullName })

  if ($DryRun) {
    Write-Output "[미리보기] $($f.Name): 이미지 $($urls.Count)장 발행 예정"
    Write-Output "  본문: $($text -replace "`n", ' / ')"
    $urls | ForEach-Object { Write-Output "  $_" }
    continue
  }

  try {
    if ($urls.Count -eq 1) {
      $cid = (Api-Post 'me/threads' @{ media_type = 'IMAGE'; image_url = $urls[0]; text = $text }).id
    } else {
      $children = foreach ($u in $urls) { (Api-Post 'me/threads' @{ media_type = 'IMAGE'; image_url = $u; is_carousel_item = 'true' }).id }
      $children | ForEach-Object { Wait-Ready $_ }
      $cid = (Api-Post 'me/threads' @{ media_type = 'CAROUSEL'; children = ($children -join ','); text = $text }).id
    }
    Wait-Ready $cid
    $mid = (Api-Post 'me/threads_publish' @{ creation_id = $cid }).id
    $link = ''
    try { $link = (Api-Get $mid 'permalink').permalink } catch { }
    $record = "발행 시각: $($now.ToString('yyyy-MM-dd HH:mm')) (KST)`r`n게시물 ID: $mid`r`n주소: $link`r`n이미지: $($urls.Count)장`r`n"
    [IO.File]::WriteAllText($done, $record, (New-Object Text.UTF8Encoding $true))
    Write-Output "[발행] $($f.Name): $link"
    $published++
  } catch {
    Write-Output "[실패] $($f.Name): $($_.Exception.Message)"
  }
}
Write-Output "발행 $published 건"
