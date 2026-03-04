param(
  [Parameter(Mandatory = $true)]
  [string]$SubscriptionId,

  [Parameter(Mandatory = $true)]
  [string]$ResourceGroup
)

$ErrorActionPreference = 'Stop'

function Invoke-AzCli {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Args,

    [Parameter(Mandatory = $true)]
    [string]$FailureMessage,

    [switch]$AllowEmpty
  )

  $result = & az @Args 2>&1
  $exitCode = $LASTEXITCODE
  $text = ($result | Out-String).Trim()

  if ($exitCode -ne 0) {
    if ($text -match 'InteractionRequired|Continuous access evaluation|LocationConditionEvaluationSatisfied') {
      throw "Azure CLI authentication challenge detected (InteractionRequired). Run 'az login --use-device-code' and complete sign-in/MFA/Conditional Access, then re-run this script."
    }

    throw "$FailureMessage`nAzure CLI output:`n$text"
  }

  if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($text)) {
    throw "$FailureMessage`nAzure CLI returned empty output."
  }

  return $text
}

Write-Host "Checking role assignment write permissions..." -ForegroundColor Cyan

$null = Invoke-AzCli -Args @('account', 'set', '--subscription', $SubscriptionId) -FailureMessage "Failed to set Azure subscription context." -AllowEmpty
$contextJson = Invoke-AzCli -Args @('account', 'show', '-o', 'json') -FailureMessage "Failed to read Azure subscription context."
$context = $contextJson | ConvertFrom-Json

$scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"

$principalIdRaw = Invoke-AzCli -Args @('ad', 'signed-in-user', 'show', '--query', 'id', '-o', 'tsv') -FailureMessage "Could not resolve signed-in user object ID."
$principalId = $principalIdRaw.Trim()
if ([string]::IsNullOrWhiteSpace($principalId)) {
  throw "Could not resolve signed-in user object ID. Ensure az login is using a user principal."
}

$assignmentsJson = Invoke-AzCli -Args @('role', 'assignment', 'list', '--assignee-object-id', $principalId, '--scope', $scope, '--include-inherited', '-o', 'json') -FailureMessage "Failed to list role assignments at scope $scope."
$assignments = $assignmentsJson | ConvertFrom-Json

if (-not $assignments -or $assignments.Count -eq 0) {
  Write-Host "FAIL: No role assignments found for principal at $scope" -ForegroundColor Red
  exit 1
}

$allowed = $false
$matchedRoles = New-Object System.Collections.Generic.List[string]

foreach ($assignment in $assignments) {
  $roleName = $assignment.roleDefinitionName
  if ([string]::IsNullOrWhiteSpace($roleName)) {
    continue
  }

  try {
    $roleDefJson = Invoke-AzCli -Args @('role', 'definition', 'list', '--name', $roleName, '-o', 'json') -FailureMessage "Failed to get role definition for '$roleName'."
  }
  catch {
    continue
  }

  $roleDef = $roleDefJson | ConvertFrom-Json
  if (-not $roleDef -or $roleDef.Count -eq 0) {
    continue
  }

  $permissions = $roleDef[0].permissions
  if (-not $permissions) {
    continue
  }

  foreach ($permission in $permissions) {
    $actions = @($permission.actions)
    $notActions = @($permission.notActions)

    $hasWrite = (
      $actions -contains '*' -or
      $actions -contains 'Microsoft.Authorization/*' -or
      $actions -contains 'Microsoft.Authorization/roleAssignments/*' -or
      $actions -contains 'Microsoft.Authorization/roleAssignments/write'
    )

    $blocked = (
      $notActions -contains 'Microsoft.Authorization/*' -or
      $notActions -contains 'Microsoft.Authorization/roleAssignments/*' -or
      $notActions -contains 'Microsoft.Authorization/roleAssignments/write'
    )

    if ($hasWrite -and -not $blocked) {
      $allowed = $true
      $matchedRoles.Add($roleName)
      break
    }
  }
}

if ($allowed) {
  $uniqueRoles = $matchedRoles | Select-Object -Unique
  Write-Host "PASS: Principal can write role assignments at $scope" -ForegroundColor Green
  Write-Host "Subscription: $($context.id)" -ForegroundColor Gray
  Write-Host "User: $($context.user.name)" -ForegroundColor Gray
  Write-Host "Roles granting access: $($uniqueRoles -join ', ')" -ForegroundColor Gray
  exit 0
}

Write-Host "FAIL: Principal lacks Microsoft.Authorization/roleAssignments/write at $scope" -ForegroundColor Red
Write-Host "Subscription: $($context.id)" -ForegroundColor Gray
Write-Host "User: $($context.user.name)" -ForegroundColor Gray
Write-Host "Ask for one of: Owner, User Access Administrator, or Role Based Access Control Administrator (scope: RG or above)." -ForegroundColor Yellow
exit 1
