<#
.SYNOPSIS
    Lumina 一键发布脚本 —— 构建 jar + 打 tag + 创建 GitHub Release

.DESCRIPTION
    1. 读取 gradle.properties 里的 mcVersion / luminaStage / luminaBuildNum
    2. 用指定 Java 构建 :lumina-server:createPaperclipJar
    3. 读取当前 git HEAD short hash，tag 格式 {mcVersion}-{hash}
    4. commit gradle.properties（若 luminaStage 改了） → push → tag → push tag
    5. gh release create 上传 paperclip jar + changelog

.USAGE
    # 1) 切到下一阶段（改 gradle.properties 里的 luminaStage / luminaBuildNum）
    #    例如：alpha → beta 或 beta.1 → beta.2
    #
    # 2) 正常提交代码：git add ... && git commit -m "..." && git push
    #
    # 3) 跑这个：
    .\scripts\release.ps1
#>

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path | Split-Path -Parent

# ========== 工具函数 ==========
function Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Die($msg)  { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# ========== 前置检查 ==========
Step "前置检查"
Set-Location $RepoRoot

$GradleProps = Join-Path $RepoRoot "gradle.properties"
if (-not (Test-Path $GradleProps)) { Die "gradle.properties 不存在" }

# 读取版本
$props = @{}
Get-Content $GradleProps | Where-Object { $_ -match '^(\w+)=(.+)$' } | ForEach-Object {
    $props[$matches[1]] = $matches[2].Trim()
}
$MC_VERSION   = $props["mcVersion"]          ?? (Die "mcVersion 未定义")
$STAGE        = $props["luminaStage"]       ?? "beta"
$BUILD_NUM    = $props["luminaBuildNum"]    ?? "1"

# Java
$JAVA_HOME = if ($env:JAVA_HOME) { $env:JAVA_HOME } elseif (Test-Path "F:\jdk25") { "F:\jdk25" } else { Die "未找到 JDK（请设 JAVA_HOME）" }
$env:JAVA_HOME = $JAVA_HOME
$env:PATH = "$JAVA_HOME\bin;$env:PATH"

# gh CLI
$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    $ghExe = "$env:ProgramFiles\GitHub CLI\gh.exe"
    if (Test-Path $ghExe) { $gh = @{ Source = $ghExe } }
    else { Die "gh CLI 未安装。先 winget install GitHub.cli" }
}
$GhExe = $gh.Source

& $GhExe auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Die "gh 未登录。先 gh auth login --web" }

$Repo     = (& git remote get-url origin).Trim() -replace '.*github\.com[:/]', '' -replace '\.git$', ''
$Branch   = (& git rev-parse --abbrev-ref HEAD).Trim()
$ShortHash = (& git rev-parse --short HEAD).Trim()
$LongHash = (& git rev-parse HEAD).Trim()
$Tag      = "$MC_VERSION-$ShortHash"
$JarName  = "lumina-$MC_VERSION-paperclip.jar"
$LocalJar = Join-Path $RepoRoot "lumina-server\build\libs\lumina-paperclip-$MC_VERSION.local-SNAPSHOT.jar"
$StagedJar = Join-Path $env:TEMP $JarName

Write-Host "  Repo       : $Repo"
Write-Host "  Branch     : $Branch"
Write-Host "  mcVersion  : $MC_VERSION"
Write-Host "  Stage      : $STAGE"
Write-Host "  BuildNum   : $BUILD_NUM"
Write-Host "  Tag        : $Tag"
Write-Host "  Java       : $JAVA_HOME"

# ========== 构建 ==========
Step "构建 paperclip jar"
Remove-Item ".gradle\configuration-cache" -Recurse -Force -ErrorAction SilentlyContinue
& .\gradlew.bat --init-script "C:\Users\Administrator\trust-all.init.gradle" `
    :lumina-server:createPaperclipJar --no-daemon --no-configuration-cache
if ($LASTEXITCODE -ne 0) { Die "构建失败" }

if (-not (Test-Path $LocalJar)) { Die "构建产物不存在: $LocalJar" }
Copy-Item $LocalJar $StagedJar -Force
$JarSize = [math]::Round((Get-Item $StagedJar).Length / 1MB, 1)
$Sha256  = (Get-FileHash $StagedJar -Algorithm SHA256).Hash.ToLower()
Write-Host "  jar   : $StagedJar"
Write-Host "  size  : $JarSize MB"
Write-Host "  sha256: $Sha256"

# 验证 manifest 版本
Add-Type -AssemblyName System.IO.Compression.FileSystem
$serverJar = Join-Path $RepoRoot "lumina-server\build\libs\lumina-server-$MC_VERSION.local-SNAPSHOT.jar"
$zip = [System.IO.Compression.ZipFile]::OpenRead($serverJar)
$mf  = $zip.GetEntry("META-INF/MANIFEST.MF")
$implVer = (New-Object System.IO.StreamReader($mf.Open())).ReadToEnd() -split "`n" |
    Where-Object { $_ -match "Implementation-Version" } | Select-Object -First 1
$zip.Dispose()
Write-Host "  manifest : $($implVer.Trim())"

# ========== tag + push ==========
Step "打 tag 并推送"

# 先看 gradle.properties 是否有未提交的改动（stage 切换）
$gpStatus = (& git status --short gradle.properties).Trim()
if ($gpStatus) {
    Write-Host "  gradle.properties 有改动，先 commit"
    & git add gradle.properties
    & git commit -m "Release Lumina $MC_VERSION ($ShortHash)"
}

# 确保当前 HEAD 没有未提交改动
$dirty = (& git status --porcelain).Trim()
if ($dirty) { Die "工作区不干净，先 commit / stash：`n$dirty" }

# 删同名旧 tag（若有）以免报错
& git tag -d $Tag 2>$null | Out-Null
& git push origin ":refs/tags/$Tag" 2>$null | Out-Null

# 打 tag
& git tag -a $Tag -m "Lumina $MC_VERSION - $ShortHash"
if ($LASTEXITCODE -ne 0) { Die "tag 失败" }

& git push origin $Tag
if ($LASTEXITCODE -ne 0) { Die "push tag 失败" }

# ========== changelog ==========
Step "生成 changelog"

# 找上一个同 repo 的 tag 来生成 diff
$prevTag = (& git tag --sort=-creatordate | Where-Object { $_ -ne $Tag } | Select-Object -First 1)
$nl = [Environment]::NewLine
if ($prevTag) {
    $commits = (& git log --format="* [%h](https://github.com/$Repo/commit/%h) %s" --no-merges "$prevTag..HEAD") -join $nl
} else {
    $commits = (& git log --format="* [%h](https://github.com/$Repo/commit/%h) %s" --no-merges -15) -join $nl
}
if (-not $commits) { $commits = "* Initial release" }

$Body = @"
📦 Version: ``$MC_VERSION`` | Commit [$ShortHash](https://github.com/$Repo/commit/$ShortHash)

SHA256: ``$Sha256``

### Branch Info

> $Branch

### Changelog

$commits
"@

# ========== 创建 Release ==========
Step "创建 GitHub Release"

# 用 --notes-file 避免 here-string 换行被吞
$NotesFile = Join-Path $env:TEMP "lumina-release-$Tag.md"
$Body | Out-File $NotesFile -Encoding utf8

# alpha / beta / rc → prerelease, release → 正式
$pre = ($STAGE -ne "release")
$releaseArgs = @("release", "create", $Tag,
    "--repo", $Repo,
    "--title", "Lumina $MC_VERSION [$STAGE] - $ShortHash",
    "--notes-file", $NotesFile,
    "--target", $Branch)
if ($pre) { $releaseArgs += "--prerelease" } else { $releaseArgs += "--latest" }
$releaseArgs += "$StagedJar#Lumina $MC_VERSION Paperclip"

& $GhExe @releaseArgs
if ($LASTEXITCODE -ne 0) { Die "gh release create 失败" }

Write-Host ""
Write-Host "✅ 发布完成！" -ForegroundColor Green
Write-Host "   https://github.com/$Repo/releases/tag/$Tag" -ForegroundColor Yellow
