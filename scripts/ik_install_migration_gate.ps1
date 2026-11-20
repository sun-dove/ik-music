param([switch]$Baseline)
$ErrorActionPreference = 'Stop'
$module = Join-Path $PSScriptRoot 'ik_install_migration.ps1'
if (-not (Test-Path -LiteralPath $module)) { throw '红门：正式迁移实现尚不存在。' }
. $module -FunctionsOnly

function Assert-Gate([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "安装迁移门失败：$Message" }
}
function Assert-Rejected([scriptblock]$Operation, [string]$Message) {
    $rejected = $false
    try { & $Operation | Out-Null } catch { $rejected = $true }
    Assert-Gate $rejected $Message
}

$old = 'D:\Applications\YueyinMusic'
$target = 'D:\Applications\ik-music'
Assert-Gate ((Get-IkInstallTarget -PreviousDirectory $old -ProgramsDirectory 'C:\Users\gate\AppData\Local\Programs') -eq $target) '旧默认叶目录应迁至同父目录ik-music'
Assert-Gate ((Get-IkInstallTarget -PreviousDirectory 'E:\Apps\MusicCustom' -ProgramsDirectory 'C:\Users\gate\AppData\Local\Programs') -eq 'E:\Apps\MusicCustom') '自定义目录必须保留'
Assert-Gate ((Get-IkInstallTarget -ProgramsDirectory 'C:\Users\gate\AppData\Local\Programs') -eq 'C:\Users\gate\AppData\Local\Programs\ik-music') '首次安装默认ik-music'
Assert-IkDirectoryPair -SourceDirectory $old -TargetDirectory $target
Assert-Rejected { Assert-IkDirectoryPair -SourceDirectory $old -TargetDirectory 'D:\' } '拒绝盘符根'
Assert-Rejected { Assert-IkDirectoryPair -SourceDirectory $old -TargetDirectory "$old\child" } '拒绝目标位于旧目录内'
Assert-Rejected { Assert-IkDirectoryPair -SourceDirectory $old -TargetDirectory 'D:\Applications' } '拒绝目标包含旧目录'
Assert-Rejected { Assert-IkDirectoryPair -SourceDirectory $old -TargetDirectory $old } '拒绝将迁移脚本当原地升级'
Assert-Rejected { Assert-IkDirectoryPair -SourceDirectory $old -TargetDirectory (Join-Path $env:WINDIR 'ik-music') } '拒绝Windows系统目录'
Assert-Rejected { Assert-IkDirectoryPair -SourceDirectory $old -TargetDirectory (Join-Path $env:APPDATA 'sun-dove/YueyinMusic') } '拒绝进入用户数据目录'

$script:events = [Collections.Generic.List[string]]::new()
$actions = @{}
foreach ($name in @('Snapshot','UninstallOld','InstallNew','Verify','UninstallFailedNew','RestoreOld')) {
    $eventName = $name
    $actions[$name] = { $script:events.Add($eventName) }.GetNewClosure()
}
Invoke-IkMigrationTransaction -Actions $actions -Baseline:$Baseline
Assert-Gate (($script:events -join ',') -eq 'Snapshot,UninstallOld,InstallNew,Verify') '必须先卸旧，再安装与验证新包'
$script:events.Clear()
$failing = $actions.Clone()
$failing.InstallNew = { $script:events.Add('InstallNew'); throw '模拟新包安装失败' }
Assert-Rejected { Invoke-IkMigrationTransaction -Actions $failing } '新安装失败需报告失败'
Assert-Gate (($script:events -join ',') -eq 'Snapshot,UninstallOld,InstallNew,UninstallFailedNew,RestoreOld') '失败必须先正确卸新再恢复旧包'
$script:events.Clear()
$failing = $actions.Clone()
$failing.UninstallOld = { $script:events.Add('UninstallOld'); throw '模拟旧程序仍占用' }
Assert-Rejected { Invoke-IkMigrationTransaction -Actions $failing } '卸旧失败需阻断'
Assert-Gate (($script:events -join ',') -eq 'Snapshot,UninstallOld') '卸旧未成功不得继续写新登记或误恢复'
$script:events.Clear()
$script:oldRemoved = $false
$failing = $actions.Clone()
$failing.UninstallOld = {
    $script:events.Add('UninstallOld')
    $script:oldRemoved = $true
    throw '模拟旧卸载和登记解除已成功，但阶段日志写入失败'
}
Assert-Rejected { Invoke-IkMigrationTransaction -Actions $failing -OldInstallationRemoved { $script:oldRemoved } } '旧卸载后的记录失败必须报告并恢复'
Assert-Gate (($script:events -join ',') -eq 'Snapshot,UninstallOld,UninstallFailedNew,RestoreOld') '旧程序已移除后日志失败也必须恢复旧包'
$script:events.Clear()
$failing = $actions.Clone()
$failing.Snapshot = { throw '模拟快照失败' }
Assert-Rejected { Invoke-IkMigrationTransaction -Actions $failing } '快照失败需阻断'
Assert-Gate ($script:events.Count -eq 0) '快照失败不得开始卸载'

$manifest = @([pscustomobject]@{ path='data\app.so'; length=12; sha256='ABC' })
Assert-Gate (Test-IkManifestEqual $manifest $manifest) '未改变数据应通过'
Assert-Gate (-not (Test-IkManifestEqual $manifest @([pscustomobject]@{path='data\app.so';length=13;sha256='ABC'}))) '必须识别数据长度变化'
Assert-Gate (-not (Test-IkManifestEqual $manifest @())) '必须识别丢失数据'
Assert-Rejected { Get-IkManifestPath -RootDirectory $target -RelativePath '..\用户音乐.mp3' } '发行清单不得越界'
Assert-Rejected { Get-IkManifestPath -RootDirectory $target -RelativePath 'C:\Windows\system.ini' } '发行清单不得包含绝对路径'
Write-Output '安装迁移确定性门通过：目录策略、越界、先卸旧、阻断、回滚和数据完整性。未操作真实安装。'
