# PowerShell script to detect new content in inbox_for_claude.txt
$inbox = 'C:/Users/storax/Desktop/webagent/inbox_for_claude.txt'
$stateFile = 'C:/Users/storax/Desktop/webagent/.last_inbox_hash'
if (-Not (Test-Path $inbox)) { Write-Error 'Inbox file not found'; exit 1 }
$content = Get-Content -Raw -Path $inbox
$hash = [System.BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($content)))
$prevHash = ''
if (Test-Path $stateFile) { $prevHash = Get-Content -Raw -Path $stateFile }
if ($hash -ne $prevHash) {
    Set-Content -Path $stateFile -Value $hash
    Write-Output $content
}
