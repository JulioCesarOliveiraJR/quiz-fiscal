# Publica no site os cards atualizados do vault.
#
#   powershell -ExecutionPolicy Bypass -File C:\dev\quiz-maria\publicar.ps1
#   powershell -ExecutionPolicy Bypass -File C:\dev\quiz-maria\publicar.ps1 -Mensagem "cards da aula 2"
#
# Faz: regenera cards.json a partir do vault -> mostra o que mudou -> commita -> push.
# Script em ASCII puro de proposito (PS 5.1 quebra com acento em .ps1 sem BOM).

[CmdletBinding()]
param(
  [string]$Mensagem,
  [string]$Repo  = 'C:\dev\quiz-maria',
  [string]$Site  = 'https://juliocesaroliveirajr.github.io/quiz-fiscal'
)

$ErrorActionPreference = 'Stop'

# ---------- 1. regenerar ----------
Write-Host "`n[1/4] Lendo os flashcards do vault..." -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File (Join-Path $Repo 'gerar-cards.ps1')
if ($LASTEXITCODE -ne 0) { throw "gerar-cards.ps1 falhou" }

# ---------- 2. o que mudou ----------
Write-Host "`n[2/4] Conferindo o que mudou..." -ForegroundColor Cyan
$mudou = git -C $Repo status --porcelain

if (-not $mudou) {
  Write-Host "Nada mudou. O site ja esta com os cards atuais do vault." -ForegroundColor Yellow
  Write-Host "  $Site/cards/"
  return
}

git -C $Repo status --short

# quantos cards antes e depois
$antes = 0
try {
  $json = git -C $Repo show HEAD:cards/cards.json 2>$null | Out-String
  if ($json) { $antes = (($json | ConvertFrom-Json).cards | Measure-Object).Count }
} catch { }
$agora = ((Get-Content (Join-Path $Repo 'cards\cards.json') -Raw -Encoding UTF8 | ConvertFrom-Json).cards | Measure-Object).Count

$delta = $agora - $antes
if ($antes -gt 0) {
  $sinal = if ($delta -gt 0) { "+$delta" } elseif ($delta -lt 0) { "$delta" } else { "sem mudanca no total" }
  Write-Host "`ncards: $antes -> $agora  ($sinal)"
}

# ---------- 3. commit ----------
Write-Host "`n[3/4] Commitando..." -ForegroundColor Cyan
if (-not $Mensagem) {
  $Mensagem = if ($delta -gt 0) { "Atualiza cards do vault (+$delta)" } else { "Atualiza cards do vault" }
}

$rodape = 'Co-Authored-By: Claude Opus 5 (1M context) ' + [char]60 + 'noreply@anthropic.com' + [char]62
$msgFinal = $Mensagem + [Environment]::NewLine + [Environment]::NewLine + $rodape

git -C $Repo add -A
git -C $Repo commit -m $msgFinal
if ($LASTEXITCODE -ne 0) { throw "commit falhou" }

# ---------- 4. push e conferencia ----------
Write-Host "`n[4/4] Enviando e aguardando o site..." -ForegroundColor Cyan
git -C $Repo push
if ($LASTEXITCODE -ne 0) { throw "push falhou" }

# Conferir pelo SHA do build do Pages, e nao pelo conteudo: quando so o HTML
# muda, a contagem de cards continua igual e o script daria "no ar" cedo demais.
$sha = (git -C $Repo rev-parse HEAD).Trim()
$ok = $false
$estado = 'desconhecido'

for ($i = 1; $i -le 25 -and -not $ok; $i++) {
  Start-Sleep -Seconds 6
  try {
    $b = gh api repos/JulioCesarOliveiraJR/quiz-fiscal/pages/builds/latest 2>$null | ConvertFrom-Json
    $estado = $b.status
    if ($b.commit -eq $sha -and $b.status -eq 'built') { $ok = $true }
    elseif ($b.commit -eq $sha -and $b.status -eq 'errored') {
      Write-Host "`n  BUILD FALHOU: $($b.error.message)" -ForegroundColor Red
      return
    }
  } catch { }
}

Write-Host ''
if ($ok) {
  Write-Host "  NO AR ($agora cards):" -ForegroundColor Green
  Write-Host "    $Site/           quiz"
  Write-Host "    $Site/cards/     cards"
  Write-Host "    $Site/simulado/  simulado"
} else {
  Write-Host "  Enviado, mas o build do Pages ainda nao terminou (estado: $estado)." -ForegroundColor Yellow
  Write-Host "  Costuma levar ate ~2 min. Confira em: $Site/"
}
