#!/usr/bin/env pwsh
# -*- coding: utf-8 -*-
<#
.SYNOPSIS
    OpenClaw 本地快速验证脚本
    武汉晴辰天下网络科技有限公司 | https://qingchencloud.com/

.DESCRIPTION
    在本地快速验证 inject_panel.py 注入脚本是否工作正常。
    避免每次修改都要等 CI 构建 30 分钟。

.PARAMETER SkipBuild
    跳过构建步骤，仅运行注入和验证（用于重复测试）

.PARAMETER Clean
    清理临时目录后重新开始

.EXAMPLE
    .\scripts\test-inject-local.ps1
    完整测试：克隆 → 构建 → 注入 → 验证

.EXAMPLE
    .\scripts\test-inject-local.ps1 -SkipBuild
    跳过构建，仅测试注入（用于修改 inject_panel.py 后快速验证）

.EXAMPLE
    .\scripts\test-inject-local.ps1 -Clean
    清理后重新开始
#>

param(
    [switch]$SkipBuild,
    [switch]$Clean
)

# 配置
$ErrorActionPreference = "Stop"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$ROOT_DIR = Split-Path -Parent $SCRIPT_DIR
$UPSTREAM_DIR = Join-Path $ROOT_DIR "openclaw"
$UPSTREAM_REPO = "https://github.com/openclaw/openclaw.git"

# 颜色输出
function Write-Step { param($msg) Write-Host "`n🔹 $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "✅ $msg" -ForegroundColor Green }
function Write-Warning { param($msg) Write-Host "⚠️ $msg" -ForegroundColor Yellow }
function Write-Error { param($msg) Write-Host "❌ $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "   $msg" -ForegroundColor Gray }

# 计时器
$startTime = Get-Date

Write-Host "`n" + "=" * 60 -ForegroundColor Blue
Write-Host "🦞 OpenClaw 本地快速验证脚本" -ForegroundColor Blue
Write-Host "=" * 60 -ForegroundColor Blue
Write-Host "📍 项目目录: $ROOT_DIR"
Write-Host "📍 上游目录: $UPSTREAM_DIR"

# 清理选项
if ($Clean) {
    Write-Step "清理临时目录..."
    if (Test-Path $UPSTREAM_DIR) {
        Remove-Item -Recurse -Force $UPSTREAM_DIR
        Write-Success "已删除 $UPSTREAM_DIR"
    }
}

# 检查依赖
Write-Step "检查依赖..."

$deps = @(
    @{ Name = "git"; Check = { git --version 2>$null } },
    @{ Name = "node"; Check = { node --version 2>$null } },
    @{ Name = "pnpm"; Check = { pnpm --version 2>$null } },
    @{ Name = "python"; Check = { python --version 2>$null } }
)

$missingDeps = @()
foreach ($dep in $deps) {
    try {
        $version = & $dep.Check
        Write-Info "$($dep.Name): $version"
    } catch {
        $missingDeps += $dep.Name
        Write-Error "$($dep.Name): 未安装"
    }
}

if ($missingDeps.Count -gt 0) {
    Write-Error "缺少依赖: $($missingDeps -join ', ')"
    exit 1
}

# 克隆或更新上游代码
if (-not $SkipBuild) {
    Write-Step "准备上游代码..."
    
    if (Test-Path $UPSTREAM_DIR) {
        Write-Info "更新现有仓库..."
        Push-Location $UPSTREAM_DIR
        try {
            git fetch --depth 1 origin main 2>&1 | Out-Null
            git reset --hard origin/main 2>&1 | Out-Null
            Write-Success "上游代码已更新"
        } catch {
            Write-Warning "更新失败，尝试重新克隆..."
            Pop-Location
            Remove-Item -Recurse -Force $UPSTREAM_DIR
            git clone --depth 1 $UPSTREAM_REPO $UPSTREAM_DIR
            Push-Location $UPSTREAM_DIR
        }
    } else {
        Write-Info "克隆上游仓库..."
        git clone --depth 1 $UPSTREAM_REPO $UPSTREAM_DIR
        Push-Location $UPSTREAM_DIR
    }
    
    Write-Info "当前目录: $(Get-Location)"
    
    # 安装依赖
    Write-Step "安装依赖 (pnpm install)..."
    & pnpm install --frozen-lockfile 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "frozen-lockfile 失败，尝试普通安装..."
        & pnpm install
    }
    Write-Success "依赖安装完成"
    
    # 构建
    Write-Step "构建项目 (pnpm build)..."
    & pnpm run build
    if ($LASTEXITCODE -ne 0) {
        Write-Error "构建失败！"
        Pop-Location
        exit 1
    }
    Write-Success "pnpm build 完成"
    
    Write-Step "构建 UI (pnpm ui:build)..."
    & pnpm run ui:build
    if ($LASTEXITCODE -ne 0) {
        Write-Error "UI 构建失败！"
        Pop-Location
        exit 1
    }
    Write-Success "pnpm ui:build 完成"
    
    Pop-Location
} else {
    Write-Step "跳过构建步骤 (-SkipBuild)"
    if (-not (Test-Path $UPSTREAM_DIR)) {
        Write-Error "上游目录不存在，请先运行完整测试"
        exit 1
    }
}

# 显示 Dashboard 目录结构
Write-Step "检查 Dashboard 目录..."
$distDir = Join-Path $UPSTREAM_DIR "dist"
if (Test-Path $distDir) {
    Write-Info "dist/ 目录内容:"
    Get-ChildItem $distDir -Directory | ForEach-Object {
        $subItems = (Get-ChildItem $_.FullName -ErrorAction SilentlyContinue | Select-Object -First 3).Name -join ", "
        Write-Info "  $($_.Name)/ ($subItems...)"
    }
} else {
    Write-Error "找不到 dist 目录！"
    exit 1
}

# 运行注入脚本
Write-Step "运行注入脚本..."
$injectScript = Join-Path (Join-Path $ROOT_DIR "scripts") "inject_panel.py"
Push-Location $ROOT_DIR
python $injectScript
$injectResult = $LASTEXITCODE
Pop-Location

if ($injectResult -ne 0) {
    Write-Error "注入脚本执行失败！"
    exit 1
}
Write-Success "注入脚本执行完成"

# 验证注入结果
Write-Step "验证注入结果..."

$searchPatterns = @("OpenClaw", "功能面板", "qingchencloud", "feature-panel")
$searchDirs = @(
    (Join-Path (Join-Path (Join-Path $UPSTREAM_DIR "dist") "canvas-host") "a2ui"),
    (Join-Path (Join-Path (Join-Path $UPSTREAM_DIR "dist") "control-ui") "assets")
)

$foundCount = 0
$totalChecks = 0

foreach ($dir in $searchDirs) {
    if (Test-Path $dir) {
        Write-Info "检查目录: $dir"
        $jsFiles = Get-ChildItem $dir -Filter "*.js" -ErrorAction SilentlyContinue
        
        foreach ($jsFile in $jsFiles) {
            $content = Get-Content $jsFile.FullName -Raw -ErrorAction SilentlyContinue
            $totalChecks++
            
            $matchCount = 0
            foreach ($pattern in $searchPatterns) {
                if ($content -match [regex]::Escape($pattern)) {
                    $matchCount++
                }
            }
            
            if ($matchCount -gt 0) {
                Write-Success "  $($jsFile.Name): 找到 $matchCount 个关键字"
                $foundCount++
            } else {
                Write-Warning "  $($jsFile.Name): 未找到关键字"
            }
        }
    }
}

# 统计关键字出现次数
Write-Step "关键字统计..."
foreach ($dir in $searchDirs) {
    if (Test-Path $dir) {
        $jsFiles = Get-ChildItem $dir -Filter "*.js" -ErrorAction SilentlyContinue
        foreach ($jsFile in $jsFiles) {
            $content = Get-Content $jsFile.FullName -Raw -ErrorAction SilentlyContinue
            $count = ([regex]::Matches($content, "OpenClaw|功能面板|qingchencloud")).Count
            if ($count -gt 0) {
                Write-Info "  $($jsFile.Name): $count 处匹配"
            }
        }
    }
}

# 结果汇总
$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host "`n" + "=" * 60 -ForegroundColor Blue
if ($foundCount -gt 0) {
    Write-Host "✅ 验证通过！" -ForegroundColor Green
    Write-Host "   注入成功的文件: $foundCount" -ForegroundColor Green
} else {
    Write-Host "❌ 验证失败！" -ForegroundColor Red
    Write-Host "   未找到注入内容" -ForegroundColor Red
}
Write-Host "   总耗时: $($duration.TotalSeconds.ToString('F1')) 秒" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Blue

# 提示下一步
Write-Host "`n💡 下一步操作:" -ForegroundColor Yellow
if ($foundCount -gt 0) {
    Write-Host "   1. 提交修改: git add . && git commit -m 'fix: ...' && git push"
    Write-Host "   2. 等待 CI 构建完成"
    Write-Host "   3. Docker 验证: docker pull ghcr.io/1186258278/openclaw-zh:nightly"
} else {
    Write-Host "   1. 检查 inject_panel.py 脚本逻辑"
    Write-Host "   2. 检查 translations/panel/ 资源文件"
    Write-Host "   3. 重新运行: .\scripts\test-inject-local.ps1 -SkipBuild"
}

exit $(if ($foundCount -gt 0) { 0 } else { 1 })
