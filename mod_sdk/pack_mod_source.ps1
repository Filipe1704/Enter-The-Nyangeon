<#
.SYNOPSIS
  从源码快照打包任意 Mod 的 PCK，不启动本体、不安装到 user://mods。

.DESCRIPTION
  与 build_coop_mod.ps1 的区别：不生成 zip、不安装，默认产出 <Source>\<ModId>.pck，支持 -Output。
  用途：无头回归脚本（tests/run_coop_session_checks.py）需要「源码即被测对象」——
  使用最小临时工程打包源目录快照，排除旧 pck，并加入唯一 mod_build.json。
  运行时同路径优先级取决于 replace_files；回归脚本只在隔离 manifest 中显式启用覆盖。

.EXAMPLE
  .\mod_sdk\pack_mod_source.ps1 -Source <源码目录> -ModId <id> -Output <目标.pck>
#>
param(
    [string]$Godot = "E:\Repos\.tools\godot\Godot_v4.7-stable_win64_console.exe",
    [string]$Project = (Split-Path -Parent $PSScriptRoot),
    [Parameter(Mandatory = $true)][string]$ModId,
    [Parameter(Mandatory = $true)][string]$Source,
    [string]$Output = "",
    [string]$BuildId = ([Guid]::NewGuid().ToString("N"))
)
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

if (-not (Test-Path -LiteralPath (Join-Path $Source "mod.json"))) {
    throw "找不到 mod.json：$Source\mod.json"
}
if (-not (Test-Path -LiteralPath $Godot)) {
    throw "找不到 Godot 可执行文件：$Godot"
}
if (-not (Test-Path -LiteralPath (Join-Path $Project "project.godot"))) {
    throw "找不到本体工程：$Project\project.godot"
}

if ($Output -eq "") {
    $Output = Join-Path $Source "$ModId.pck"
}
$outPck = [IO.Path]::GetFullPath($Output)
$taskTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$taskPackRoot = Join-Path $taskTempRoot ("etn-mod-pack-" + [Guid]::NewGuid().ToString("N"))
$stage = Join-Path $taskPackRoot "source"
$tmpPck = Join-Path $taskPackRoot "$ModId.pck"
$taskEnvironmentBackup = @{}
try {
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    # 从快照打包，不修改源目录或把旧 pck 再装进新包。
    Get-ChildItem -LiteralPath $Source -Recurse -File | Where-Object {
        $_.Extension -ne ".pck"
    } | ForEach-Object {
        $relative = [IO.Path]::GetRelativePath([IO.Path]::GetFullPath($Source), $_.FullName)
        $target = Join-Path $stage $relative
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($target)) -Force | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $target
    }
    $stamp = @{ build_id = $BuildId } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText((Join-Path $stage "mod_build.json"), $stamp, [Text.UTF8Encoding]::new($false))
    # 最小工程不加载本体 autoload；隔离 user://，打包也不接触已安装 MOD。
    [IO.File]::WriteAllText((Join-Path $taskPackRoot "project.godot"), "config_version=5`n", [Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath (Join-Path $Project "mod_sdk/pack_mod.gd") -Destination (Join-Path $taskPackRoot "pack_mod.gd")
    foreach ($key in @("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME")) {
        $taskEnvironmentBackup[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
        $isolatedPath = Join-Path $taskPackRoot $key
        New-Item -ItemType Directory -Path $isolatedPath -Force | Out-Null
        [Environment]::SetEnvironmentVariable($key, $isolatedPath, "Process")
    }
    $packOutput = & $Godot --headless --path $taskPackRoot --script res://pack_mod.gd -- `
        "--mod-source=$stage" "--out=$tmpPck" "--mod-id=$ModId" 2>&1
    $packExitCode = $LASTEXITCODE
    if ($packExitCode -ne 0 -or -not (Test-Path -LiteralPath $tmpPck) -or
        ($packOutput -match "SCRIPT ERROR|ERROR:|add_file failed")) {
        throw "打包失败：$($packOutput -join [Environment]::NewLine)"
    }
    $packOutput | Select-String "PACK_MOD" | ForEach-Object { $_.Line }
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($outPck)) -Force | Out-Null
    Move-Item -LiteralPath $tmpPck -Destination $outPck -Force
    $size = (Get-Item -LiteralPath $outPck).Length
    Write-Host "已生成：$outPck（$size 字节，build=$BuildId）"
} finally {
    foreach ($key in $taskEnvironmentBackup.Keys) {
        [Environment]::SetEnvironmentVariable($key, $taskEnvironmentBackup[$key], "Process")
    }
    # 只递归删除本次新建且位于系统临时目录内的唯一目录。
    $resolvedPackRoot = [IO.Path]::GetFullPath($taskPackRoot)
    if (-not $resolvedPackRoot.StartsWith($taskTempRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolvedPackRoot) -notlike "etn-mod-pack-*") {
        throw "拒绝清理异常临时路径：$resolvedPackRoot"
    }
    if (Test-Path -LiteralPath $resolvedPackRoot) {
        Remove-Item -LiteralPath $resolvedPackRoot -Recurse -Force
    }
}
