# 毎日10時のタスクスケジューラから呼び出され、Dropboxデスクトップアプリの同期フォルダ
# （既定パスは fetch_estimate_data.py の --local-root 既定値）から見積データ抽出.xlsxを
# 読み込んで assets/data/estimate_YYYY_MM.json / index.json を更新するラッパー。
# Dropbox APIトークンは不要（ローカル同期フォルダを直接読むため）。

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}
$logFile = Join-Path $logDir ("fetch_estimate_data_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

Set-Location $repoRoot

python "scripts\fetch_estimate_data.py" *>&1 | Tee-Object -FilePath $logFile
$fetchExitCode = $LASTEXITCODE

$changed = git status --porcelain -- assets/data
if ($changed) {
    "assets/data changed, committing locally" | Tee-Object -FilePath $logFile -Append
    git add assets/data | Out-Null
    $commitMessage = "Auto-update estimate data ({0:yyyy-MM-dd})" -f (Get-Date)
    git commit -m $commitMessage *>&1 | Tee-Object -FilePath $logFile -Append | Out-Null
} else {
    "assets/data unchanged, skipping commit" | Tee-Object -FilePath $logFile -Append
}

# ローカルにコミット済みで未pushの分（このタスク以外での手動コミット分も含む）を
# まとめてpushし、GitHub Pages(Web版)にも自動反映する。
# Web版は upstream(nishimura1694/ZAIKIapp) 側のリポジトリで配信されているため、
# origin ではなく upstream に直接pushする。
git fetch upstream main *>&1 | Tee-Object -FilePath $logFile -Append | Out-Null
$ahead = git rev-list --count 'upstream/main..HEAD' 2>$null
$behind = git rev-list --count 'HEAD..upstream/main' 2>$null
if ([int]$behind -gt 0) {
    "local main is $behind commit(s) behind upstream/main, merging" | Tee-Object -FilePath $logFile -Append
    git merge upstream/main -m "Merge upstream/main" *>&1 | Tee-Object -FilePath $logFile -Append | Out-Null
}
if ([int]$ahead -gt 0 -or [int]$behind -gt 0) {
    "pushing to upstream" | Tee-Object -FilePath $logFile -Append
    git push upstream main *>&1 | Tee-Object -FilePath $logFile -Append | Out-Null
    if ($LASTEXITCODE -ne 0) {
        "git push to upstream failed (exit $LASTEXITCODE)" | Tee-Object -FilePath $logFile -Append
    }
} else {
    "nothing to push" | Tee-Object -FilePath $logFile -Append
}

exit $fetchExitCode
