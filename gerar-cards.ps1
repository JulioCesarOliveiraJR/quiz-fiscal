# Le as notas de flashcard do vault FaculMaria e gera cards/cards.json para o site.
#
#   powershell -ExecutionPolicy Bypass -File C:\dev\quiz-maria\gerar-cards.ps1
#
# Formato esperado nas notas (o mesmo do plugin Spaced Repetition do Obsidian):
#
#   ## Secao
#
#   **Pergunta**
#   ?
#   Resposta, que pode ter varias linhas.
#
#   ---

[CmdletBinding()]
param(
  [string]$Vault = 'C:\dev\FaculMaria',
  [string]$Saida = 'C:\dev\quiz-maria\cards\cards.json'
)

$ErrorActionPreference = 'Stop'

function ConvertTo-Html([string]$md) {
  $t = $md.Trim()
  # escapa HTML antes de reintroduzir a formatacao
  $t = $t -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
  $t = [regex]::Replace($t, '`([^`]+)`', '<code>$1</code>')
  $t = [regex]::Replace($t, '\*\*([^*]+)\*\*', '<strong>$1</strong>')
  $t = [regex]::Replace($t, '(?<![\*\w])\*([^*\n]+)\*(?!\*)', '<em>$1</em>')
  $t = [regex]::Replace($t, '\[\[([^\]\|]+)\|([^\]]+)\]\]', '$2')   # [[nota|texto]] -> texto
  $t = [regex]::Replace($t, '\[\[([^\]]+)\]\]', '$1')               # [[nota]]       -> nota
  $t = $t -replace "`r`n", "`n"
  $t = $t -replace "`n", '<br>'
  return $t
}

# pasta localizada por curinga: o nome tem acento e o parser do PS 5.1
# quebra com .ps1 UTF-8 sem BOM, entao este script fica em ASCII puro.
$pastaRevisao = Get-ChildItem -LiteralPath $Vault -Directory |
                Where-Object { $_.Name -like '03 - *' } | Select-Object -First 1
if (-not $pastaRevisao) { throw "Nao achei a pasta '03 - Revisao' em $Vault" }

$arquivos = Get-ChildItem -LiteralPath $pastaRevisao.FullName -Filter 'Flashcards*.md' | Sort-Object Name
if (-not $arquivos) { throw "Nenhuma nota de flashcard encontrada." }

$materias = @()

foreach ($arq in $arquivos) {
  $nome = $arq.BaseName -replace '^Flashcards\s*-\s*', ''
  $linhas = Get-Content -LiteralPath $arq.FullName -Encoding UTF8

  $cards = @()
  $secao = ''
  $bloco = @()
  $noFrontmatter = $false
  $primeiraLinha = $true

  function Fechar-Bloco {
    param($bloco, $secao)
    $idx = -1
    for ($i = 0; $i -lt $bloco.Count; $i++) {
      if ($bloco[$i].Trim() -eq '?') { $idx = $i; break }
    }
    if ($idx -lt 1) { return $null }
    $p = ($bloco[0..($idx - 1)] -join "`n").Trim()
    $r = if ($idx + 1 -le $bloco.Count - 1) { ($bloco[($idx + 1)..($bloco.Count - 1)] -join "`n").Trim() } else { '' }
    if (-not $p -or -not $r) { return $null }
    return [pscustomobject]@{
      p = ConvertTo-Html $p
      r = ConvertTo-Html $r
      s = $secao
    }
  }

  foreach ($l in $linhas) {
    $t = $l.Trim()

    # frontmatter
    if ($primeiraLinha -and $t -eq '---') { $noFrontmatter = $true; $primeiraLinha = $false; continue }
    $primeiraLinha = $false
    if ($noFrontmatter) { if ($t -eq '---') { $noFrontmatter = $false }; continue }

    if ($t -match '^##\s+(.+)') { $secao = $Matches[1].Trim(); $bloco = @(); continue }
    if ($t -match '^#\s')       { $bloco = @(); continue }

    if ($t -eq '---') {
      $c = Fechar-Bloco $bloco $secao
      if ($c) { $cards += $c }
      $bloco = @()
      continue
    }
    $bloco += $l
  }
  $c = Fechar-Bloco $bloco $secao
  if ($c) { $cards += $c }

  if ($cards.Count) {
    $materias += [pscustomobject]@{
      materia = $nome
      cards   = $cards
    }
    "{0,3} cards  <-  {1}" -f $cards.Count, $arq.Name
  }
}

$total = ($materias | ForEach-Object { $_.cards.Count } | Measure-Object -Sum).Sum

New-Item -ItemType Directory -Force -Path (Split-Path $Saida) | Out-Null
$json = $materias | ConvertTo-Json -Depth 6 -Compress
[System.IO.File]::WriteAllText($Saida, $json, (New-Object System.Text.UTF8Encoding $false))

""
"$total cards em $($materias.Count) materias -> $Saida"
"{0:N0} KB" -f ((Get-Item $Saida).Length / 1KB)
