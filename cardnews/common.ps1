# 카드뉴스 공용 함수 (make.ps1, publish.ps1 에서 불러 씀). Windows PowerShell 5.1 / PowerShell 7 겸용.
$script:KeyMap = @{ '스타일'='style'; '태그'='tag'; '제목'='title'; '부제'='sub'; '사진'='img'; '본문'='body'; '발행'='publish'; '링크'='link' }
$script:PostsDir = Join-Path $PSScriptRoot 'posts'
$script:CardsDirName = '카드뉴스'
$script:DoneFileName = '발행완료.txt'
$script:SiteUrl = 'https://gim481976-afk.github.io/yeongyeong-store/'

function Parse-Block([string[]]$lines) {
  $o = @{}; $last = $null
  foreach ($l in $lines) {
    if ($l -match '^\s*([^:：]+?)\s*[:：]\s*(.*)$' -and $script:KeyMap.ContainsKey($matches[1].Trim())) {
      $last = $script:KeyMap[$matches[1].Trim()]
      $o[$last] = $matches[2].Trim()
    } elseif ($l.Trim() -and $last -eq 'body') {
      $o['body'] += "`n" + $l.TrimEnd()   # 본문은 여러 줄 허용
    }
  }
  $o
}

# 글.txt 읽기 → @{ Head = @{...}; Cards = @(@{...}, ...) }
function Read-Post([string]$folder) {
  $txt = Join-Path $folder '글.txt'
  if (-not (Test-Path $txt)) { return $null }
  $raw = [IO.File]::ReadAllText($txt, [Text.Encoding]::UTF8)
  $blocks = $raw -split '(?m)^\s*-{3,}\s*$'
  @{
    Head  = Parse-Block ($blocks[0] -split "`r?`n")
    Cards = @($blocks | Select-Object -Skip 1 | ForEach-Object { Parse-Block ($_ -split "`r?`n") } | Where-Object { $_.Count })
  }
}

# "2026-12-03 10:00" (한국 시간) → DateTimeOffset, 형식이 틀리면 $null
function Parse-KstTime([string]$s) {
  if (-not $s) { return $null }
  $s = $s.Trim() -replace '\.', '-'
  foreach ($fmt in 'yyyy-MM-dd HH:mm', 'yyyy-MM-dd H:mm', 'yyyy-MM-dd') {
    $dt = [datetime]::MinValue
    if ([datetime]::TryParseExact($s, $fmt, [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$dt)) {
      return New-Object DateTimeOffset ($dt, [TimeSpan]::FromHours(9))
    }
  }
  $null
}

function Get-Photos([string]$folder) {
  @(Get-ChildItem $folder -File | Where-Object { $_.Extension -match '^\.(jpe?g|png|webp)$' } | Sort-Object Name)
}

function Find-Browser {
  $c = @($env:CHROME_PATH,
         "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
         "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
         "$env:ProgramFiles\Google\Chrome\Application\chrome.exe") | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
  if ($c) { return $c }
  foreach ($n in 'google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser') {
    $cmd = Get-Command $n -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
  }
  $null
}
