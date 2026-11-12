# 카드뉴스 자동 생성
# cardnews\posts\ 아래 폴더마다: 사진들 + 글.txt  →  같은 폴더의 카드뉴스\ 에 PNG 생성
# 사용: powershell -ExecutionPolicy Bypass -File cardnews\make.ps1 [-Post 폴더이름] [-Force]
param([string]$Post = '', [switch]$Force)
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'common.ps1')

$browser = Find-Browser
if (-not $browser) { Write-Output '[오류] Edge/Chrome 브라우저를 찾을 수 없습니다.'; exit 1 }
$tpl = ([System.Uri](Join-Path $PSScriptRoot 'template.html')).AbsoluteUri
$onLinux = ($PSVersionTable.PSEdition -eq 'Core') -and $IsLinux
$styleMap = @{ '표지'='cover'; '액자'='frame'; '꽉찬'='full'; 'cover'='cover'; 'frame'='frame'; 'full'='full' }

$folders = Get-ChildItem $PostsDir -Directory | Where-Object { -not $Post -or $_.Name -eq $Post } | Sort-Object Name
if (-not $folders) { Write-Output 'posts 폴더에 게시물 폴더가 없습니다.'; exit 0 }

foreach ($f in $folders) {
  $p = Read-Post $f.FullName
  $out = Join-Path $f.FullName $CardsDirName
  if (-not $p) { Write-Output "[건너뜀] $($f.Name): 글.txt 없음"; continue }
  if ((Test-Path $out) -and -not $Force) { Write-Output "[건너뜀] $($f.Name): 이미 만들어짐"; continue }
  if (-not $p.Cards.Count) { Write-Output "[건너뜀] $($f.Name): --- 아래 카드 내용이 없음"; continue }
  if ($p.Head.publish -and -not (Parse-KstTime $p.Head.publish)) { Write-Output "[주의] $($f.Name): 발행 시간 형식이 틀림 (예: 2026-12-03 10:00)" }

  $photos = Get-Photos $f.FullName
  if (Test-Path $out) { Remove-Item $out -Recurse -Force }
  New-Item -ItemType Directory $out | Out-Null
  $n = $p.Cards.Count
  for ($i = 0; $i -lt $n; $i++) {
    $c = $p.Cards[$i]
    $styleName = if ($c.style) { $c.style } elseif ($p.Head.style) { $p.Head.style } else { '액자' }
    $style = $styleMap[$styleName]
    if (-not $style) { $style = 'frame' }
    $photo = if ($c.img) { Get-Item (Join-Path $f.FullName $c.img) -ErrorAction SilentlyContinue } elseif ($photos.Count) { $photos[[math]::Min($i, $photos.Count - 1)] } else { $null }
    if (-not $photo) { Write-Output "[오류] $($f.Name) 카드 $($i+1): 사진 없음"; continue }
    $page = if ($style -eq 'cover') { '' } else { "$($i+1)/$n" }
    $title = ([string]$c.title -replace '\s*/\s*', '|')
    $qs = @(
      ('style=' + $style),
      ('img='   + [Uri]::EscapeDataString(([System.Uri]$photo.FullName).AbsoluteUri)),
      ('tag='   + [Uri]::EscapeDataString([string]$c.tag)),
      ('title=' + [Uri]::EscapeDataString($title)),
      ('sub='   + [Uri]::EscapeDataString([string]$c.sub)),
      ('page='  + [Uri]::EscapeDataString($page))
    ) -join '&'
    $png = Join-Path $out ('{0:D2}.png' -f ($i + 1))
    $bargs = @('--headless=new', '--disable-gpu', '--hide-scrollbars', '--allow-file-access-from-files',
               '--virtual-time-budget=6000', '--window-size=1080,1350', "--screenshot=$png")
    if ($onLinux) { $bargs += @('--no-sandbox', '--force-device-scale-factor=1') }
    & $browser @bargs "$tpl`?$qs" 2>&1 | Out-Null
  }
  if ($p.Head.body) { [IO.File]::WriteAllText((Join-Path $out '본문.txt'), $p.Head.body, (New-Object Text.UTF8Encoding $true)) }
  Write-Output "[완료] $($f.Name): 카드 $n 장"
}
