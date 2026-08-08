param(
    [Parameter(Mandatory=$true)] [string]$ProjectId,
    [Parameter(Mandatory=$true)] [string]$SendGridKey,
    [Parameter(Mandatory=$true)] [string]$SendGridFrom
)

function Exit-WithError([string]$msg, [int]$code=1) {
    Write-Error $msg
    Exit $code
}

if (-not (Get-Command firebase -ErrorAction SilentlyContinue)) {
    Exit-WithError "Firebase CLI not found in PATH. Install and login: https://firebase.google.com/docs/cli"
}

$orig = Get-Location
Set-Location -Path (Join-Path $PSScriptRoot '.')

try {
    Write-Host "Setting SendGrid config for project '$ProjectId'..."
    firebase functions:config:set sendgrid.key="$SendGridKey" sendgrid.from="$SendGridFrom" --project $ProjectId

    Write-Host "Deploying function 'processInvitation' to project '$ProjectId'..."
    firebase deploy --only functions:processInvitation --project $ProjectId
    Write-Host "Deploy finished. Check logs if you need details: firebase functions:log --only processInvitation --project $ProjectId"
} catch {
    Exit-WithError "Deploy failed: $_"
} finally {
    Set-Location -Path $orig
}
