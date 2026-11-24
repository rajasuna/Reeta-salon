[CmdletBinding()]
param(
  [string]$SourcePath = 'C:\Users\Lenovo\salon-pro',
  [string]$CustomDomain
)

$ErrorActionPreference = 'Stop'
$mainBranch = 'main'
$domainPattern = '^(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$'

function Get-SourceFiles {
  param(
    [Parameter(Mandatory = $true)][string]$Directory,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$RelativeDirectory,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Files
  )

  foreach ($entry in Get-ChildItem -LiteralPath $Directory -Force -ErrorAction Stop) {
    if ($entry.Name -ieq '.git' -or $entry.Name -ieq '.github') {
      continue
    }
    if (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
      continue
    }

    $relativePath = if ($RelativeDirectory) {
      Join-Path $RelativeDirectory $entry.Name
    } else {
      $entry.Name
    }

    if ($entry.PSIsContainer) {
      Get-SourceFiles -Directory $entry.FullName -RelativeDirectory $relativePath -Files $Files
      continue
    }

    $gitPath = $relativePath.Replace('\', '/')
    if ($gitPath -ieq 'CNAME' -or $gitPath -ieq 'scripts/sync-salon-pro.ps1') {
      continue
    }
    [void]$Files.Add([pscustomobject]@{
      File = $entry
      RelativePath = $relativePath
    })
  }
}

if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
  throw "Source folder not found: $SourcePath"
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
$gitRootOutput = & git -C $repoRoot rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) {
  throw "Could not locate the destination Git repository at $repoRoot."
}
$gitRoot = [System.IO.Path]::GetFullPath(($gitRootOutput | Select-Object -First 1)).TrimEnd('\', '/')
if (-not [string]::Equals($repoRoot, $gitRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "The helper must be run from its repository checkout; resolved Git root: $gitRoot"
}

$sourceRoot = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $SourcePath).Path).TrimEnd('\', '/')
$separator = [System.IO.Path]::DirectorySeparatorChar
$sourcePrefix = $sourceRoot + $separator
$repoPrefix = $repoRoot + $separator
if (
  [string]::Equals($sourceRoot, $repoRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
  $sourceRoot.StartsWith($repoPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
  $repoRoot.StartsWith($sourcePrefix, [System.StringComparison]::OrdinalIgnoreCase)
) {
  throw 'The source and destination must be separate, non-nested folders.'
}

$branch = (& git -C $repoRoot branch --show-current).Trim()
if ($LASTEXITCODE -ne 0 -or $branch -ne $mainBranch) {
  throw "Check out the $mainBranch branch in this Reeta-salon checkout before syncing (current: $branch)."
}
$origin = & git -C $repoRoot remote get-url origin
if ($LASTEXITCODE -ne 0 -or -not $origin) {
  throw 'The destination checkout must have an origin remote.'
}

# Refuse to push unrelated local commits; fetch updates only the remote-tracking ref.
& git -C $repoRoot fetch origin $mainBranch
if ($LASTEXITCODE -ne 0) {
  throw 'Could not fetch origin/main. No commit or push was attempted.'
}
$localHead = (& git -C $repoRoot rev-parse HEAD).Trim()
$remoteHead = (& git -C $repoRoot rev-parse "refs/remotes/origin/$mainBranch").Trim()
if ($LASTEXITCODE -ne 0 -or $localHead -ne $remoteHead) {
  throw 'Local main must match origin/main before syncing. Review or push existing commits separately, then retry.'
}

if ($PSBoundParameters.ContainsKey('CustomDomain')) {
  if ($CustomDomain.Length -gt 253 -or $CustomDomain -notmatch $domainPattern) {
    throw 'CustomDomain must be a hostname only, such as reetasalon.is-a.dev.'
  }
}

$sourceFiles = New-Object 'System.Collections.Generic.List[object]'
Get-SourceFiles -Directory $sourceRoot -RelativeDirectory '' -Files $sourceFiles
if ($sourceFiles.Count -eq 0) {
  throw "No source files were found to sync from $sourceRoot."
}

$changedPaths = New-Object 'System.Collections.Generic.List[string]'
foreach ($sourceFile in $sourceFiles) {
  $destinationPath = Join-Path $repoRoot $sourceFile.RelativePath
  $needsCopy = -not (Test-Path -LiteralPath $destinationPath -PathType Leaf)
  if (-not $needsCopy) {
    $sourceHash = (Get-FileHash -LiteralPath $sourceFile.File.FullName -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash
    $needsCopy = $sourceHash -ne $destinationHash
  }

  if ($needsCopy) {
    $destinationDirectory = Split-Path -Parent $destinationPath
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
      New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }
    Copy-Item -LiteralPath $sourceFile.File.FullName -Destination $destinationPath -Force
    [void]$changedPaths.Add($sourceFile.RelativePath.Replace('\', '/'))
  }
}

if ($PSBoundParameters.ContainsKey('CustomDomain')) {
  $cnamePath = Join-Path $repoRoot 'CNAME'
  $existingDomain = ''
  if (Test-Path -LiteralPath $cnamePath -PathType Leaf) {
    $existingContent = [System.IO.File]::ReadAllText($cnamePath)
    $existingDomain = $existingContent.TrimEnd([char[]]@(13, 10))
  }

  if (-not [string]::Equals($existingDomain, $CustomDomain, [System.StringComparison]::OrdinalIgnoreCase)) {
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($cnamePath, $CustomDomain + [Environment]::NewLine, $utf8WithoutBom)
    [void]$changedPaths.Add('CNAME')
  }
}

$changedPaths = @($changedPaths | Sort-Object -Unique)
if ($changedPaths.Count -eq 0) {
  Write-Output 'Source files already match; nothing was committed or pushed.'
  return
}

# Literal pathspecs ensure only files changed by this sync are staged and committed.
$pathspecs = @($changedPaths | ForEach-Object { ':(literal)' + $_ })
& git -C $repoRoot add -- @pathspecs
if ($LASTEXITCODE -ne 0) {
  throw 'Could not stage the synced paths.'
}

& git -C $repoRoot diff --cached --quiet -- @pathspecs
if ($LASTEXITCODE -eq 0) {
  Write-Output 'The synced paths have no changes to commit.'
  return
}
if ($LASTEXITCODE -ne 1) {
  throw 'Could not check the staged sync paths.'
}

$commitMessage = if ($PSBoundParameters.ContainsKey('CustomDomain')) {
  'Sync salon-pro site files and custom domain'
} else {
  'Sync salon-pro site files'
}
& git -C $repoRoot commit --only -m $commitMessage -- @pathspecs
if ($LASTEXITCODE -ne 0) {
  throw 'Could not commit the synced paths.'
}

# Pushing main triggers the repository's native branch-based GitHub Pages deployment.
& git -C $repoRoot push origin $mainBranch
if ($LASTEXITCODE -ne 0) {
  throw 'The sync commit was created, but pushing main failed.'
}

Write-Output "Pushed the following changed paths to origin/${mainBranch}:"
$changedPaths | ForEach-Object { Write-Output "  $_" }
