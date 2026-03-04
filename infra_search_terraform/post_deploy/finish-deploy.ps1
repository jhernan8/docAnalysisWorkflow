param(
  [Parameter(Mandatory = $true)]
  [string]$ResourceGroupName,

  [string]$TerraformDir = "..",
  [string]$ProjectName = "contract-search-project",
  [string]$IndexName = "contracts-index",
  [string]$SkillsetName = "contracts-skillset",
  [string]$DataSourceName = "contracts-datasource",
  [string]$IndexerName = "contracts-indexer",
  [string]$BlobContainerName = "contracts",
  [string]$EmbeddingDeploymentName = "text-embedding-3-large",
  [string]$EmbeddingModelName = "text-embedding-3-large",
  [string]$EmbeddingModelVersion = "1",
  [string]$EmbeddingDeploymentSkuName = "GlobalStandard",
  [int]$EmbeddingDeploymentCapacity = 120,
  [string]$SkillsetTemplatePath = "..\index_configs\completeSKillset.json",
  [string]$IndexerTemplatePath = "..\index_configs\indexer.json",
  [string]$VersionSuffix = "v2",
  [string]$SearchApiVersion = "2024-07-01",
  [string]$SkillsetApiVersion = "2025-11-01-Preview",
  [switch]$DisableAutoVersionOnIncompatibleIndex,

  [string]$AdminAiAccountName,

  [switch]$SkipRbac,
  [switch]$SkipFoundryProject,
  [switch]$SkipSearchObjects,
  [switch]$SkipEnableAllowProjectManagement
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
  Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Info([string]$Message) {
  Write-Host "[info] $Message" -ForegroundColor Gray
}

function Write-WarnLine([string]$Message) {
  Write-Host "[warn] $Message" -ForegroundColor Yellow
}

function Write-Ok([string]$Message) {
  Write-Host "[ok]   $Message" -ForegroundColor Green
}

function Require-Cli([string]$CommandName) {
  if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
    throw "Required command '$CommandName' was not found in PATH."
  }
}

function Get-NameFromResourceId([string]$ResourceId) {
  if ([string]::IsNullOrWhiteSpace($ResourceId)) {
    return $null
  }
  return ($ResourceId -split "/")[-1]
}

function Ensure-AiDeployment(
  [string]$ResourceGroupName,
  [string]$AccountName,
  [string]$DeploymentName,
  [string]$ModelName,
  [string]$ModelVersion,
  [string]$SkuName,
  [int]$Capacity
) {
  if ([string]::IsNullOrWhiteSpace($AccountName)) {
    throw "AI account name is empty while ensuring deployment '$DeploymentName'."
  }
  if ([string]::IsNullOrWhiteSpace($DeploymentName)) {
    throw "Embedding deployment name is empty."
  }
  if ([string]::IsNullOrWhiteSpace($ModelName)) {
    throw "Embedding model name is empty."
  }
  if ([string]::IsNullOrWhiteSpace($ModelVersion)) {
    throw "Embedding model version is empty."
  }
  if ([string]::IsNullOrWhiteSpace($SkuName)) {
    throw "Embedding deployment sku name is empty."
  }
  if ($Capacity -lt 1) {
    throw "Embedding deployment capacity must be >= 1."
  }

  $deploymentsJson = az cognitiveservices account deployment list --name $AccountName --resource-group $ResourceGroupName -o json 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($deploymentsJson)) {
    throw "Could not list deployments for AI account '$AccountName'. Verify Azure CLI permissions and account settings."
  }

  $deployments = $deploymentsJson | ConvertFrom-Json
  $match = $deployments | Where-Object { $_.name -eq $DeploymentName } | Select-Object -First 1
  if ($null -ne $match) {
    Write-Info "Embedding deployment already exists: $DeploymentName"
    return
  }

  Write-Info "Creating embedding deployment '$DeploymentName' on '$AccountName' (model=$ModelName, version=$ModelVersion, capacity=$Capacity)."
  az cognitiveservices account deployment create `
    --name $AccountName `
    --resource-group $ResourceGroupName `
    --deployment-name $DeploymentName `
    --model-format "OpenAI" `
    --model-name $ModelName `
    --model-version $ModelVersion `
    --sku-name $SkuName `
    --sku-capacity $Capacity `
    --only-show-errors | Out-Null

  if ($LASTEXITCODE -ne 0) {
    throw "Failed to create Azure OpenAI deployment '$DeploymentName' in account '$AccountName'."
  }

  $verifyJson = az cognitiveservices account deployment list --name $AccountName --resource-group $ResourceGroupName -o json 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($verifyJson)) {
    throw "Deployment '$DeploymentName' create command ran, but verification list failed."
  }

  $verified = ($verifyJson | ConvertFrom-Json) | Where-Object { $_.name -eq $DeploymentName } | Select-Object -First 1
  if ($null -eq $verified) {
    throw "Deployment '$DeploymentName' was not found after creation attempt."
  }

  Write-Ok "Embedding deployment created: $DeploymentName"
}

function Ensure-RoleAssignment(
  [string]$PrincipalId,
  [string]$PrincipalType,
  [string]$RoleName,
  [string]$Scope
) {
  if ([string]::IsNullOrWhiteSpace($PrincipalId)) {
    Write-WarnLine "Skipping role '$RoleName' at '$Scope' because principal id is empty."
    return
  }

  $existing = az role assignment list `
    --assignee-object-id $PrincipalId `
    --role $RoleName `
    --scope $Scope `
    --query "[0].id" -o tsv 2>$null

  if (-not [string]::IsNullOrWhiteSpace($existing)) {
    Write-Info "Role already present: $RoleName ($PrincipalId)"
    return
  }

  az role assignment create `
    --assignee-object-id $PrincipalId `
    --assignee-principal-type $PrincipalType `
    --role $RoleName `
    --scope $Scope `
    --only-show-errors | Out-Null

  Write-Ok "Assigned '$RoleName' to $PrincipalId"
}

function Ensure-StorageContainer([string]$AccountName, [string]$ContainerName) {
  $storageAccountId = az storage account show --name $AccountName --query id -o tsv 2>$null
  if ([string]::IsNullOrWhiteSpace($storageAccountId)) {
    throw "Could not resolve storage account id for '$AccountName'."
  }

  $containerUri = "https://management.azure.com${storageAccountId}/blobServices/default/containers/${ContainerName}?api-version=2023-05-01"
  $tmp = [System.IO.Path]::GetTempFileName()
  try {
    (@{ properties = @{} } | ConvertTo-Json -Depth 5) | Set-Content -Path $tmp -Encoding utf8
    Invoke-AzRestChecked -Method "PUT" -Uri $containerUri -Resource "" -BodyFile $tmp
    Write-Ok "Blob container ensured: $ContainerName"
  }
  finally {
    Remove-Item -Path $tmp -ErrorAction SilentlyContinue
  }
}

function Invoke-AzRestChecked(
  [string]$Method,
  [string]$Uri,
  [string]$Resource,
  [string]$BodyFile,
  [int]$MaxAttempts = 1,
  [int]$DelaySeconds = 0
) {
  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    $args = @("rest", "--method", $Method, "--uri", $Uri, "--only-show-errors")
    if (-not [string]::IsNullOrWhiteSpace($Resource)) {
      $args += @("--resource", $Resource)
    }
    if (-not [string]::IsNullOrWhiteSpace($BodyFile)) {
      $args += @("--headers", "Content-Type=application/json", "--body", "@$BodyFile")
    }

    $result = & az @args 2>&1
    if ($LASTEXITCODE -eq 0) {
      return
    }

    if ($attempt -lt $MaxAttempts) {
      Write-WarnLine "Request failed (attempt $attempt/$MaxAttempts). Retrying in $DelaySeconds seconds..."
      if ($DelaySeconds -gt 0) {
        Start-Sleep -Seconds $DelaySeconds
      }
      continue
    }

    $output = ($result | Out-String).Trim()
    throw "az rest failed for $Method $Uri`n$output"
  }
}

function Invoke-SearchPut([string]$Uri, [object]$Body, [int]$MaxAttempts = 1, [int]$DelaySeconds = 0) {
  $tmp = [System.IO.Path]::GetTempFileName()
  try {
    $Body | ConvertTo-Json -Depth 20 | Set-Content -Path $tmp -Encoding utf8
    Invoke-AzRestChecked -Method "PUT" -Uri $Uri -Resource "https://search.azure.com" -BodyFile $tmp -MaxAttempts $MaxAttempts -DelaySeconds $DelaySeconds
  }
  finally {
    Remove-Item -Path $tmp -ErrorAction SilentlyContinue
  }
}

Require-Cli "az"
Require-Cli "terraform"

Write-Step "Checking Azure login"
$subscriptionId = az account show --query id -o tsv
if ([string]::IsNullOrWhiteSpace($subscriptionId)) {
  throw "Azure CLI is not logged in. Run: az login"
}
Write-Ok "Using subscription $subscriptionId"

Write-Step "Reading Terraform outputs"
Push-Location $PSScriptRoot
try {
  $tfDirResolved = (Resolve-Path -Path $TerraformDir).Path
  $tfJson = terraform "-chdir=$tfDirResolved" output -json
}
finally {
  Pop-Location
}

if ([string]::IsNullOrWhiteSpace($tfJson)) {
  throw "Terraform outputs are empty. Run terraform apply first."
}

$tf = $tfJson | ConvertFrom-Json

$searchServiceId = $tf.search_service_id.value
$storageAccountId = $tf.storage_account_id.value
$logicAppId = $tf.logic_app_id.value

if ([string]::IsNullOrWhiteSpace($searchServiceId) -or [string]::IsNullOrWhiteSpace($storageAccountId) -or [string]::IsNullOrWhiteSpace($logicAppId)) {
  throw "Missing required outputs (search_service_id, storage_account_id, logic_app_id)."
}

$searchServiceName = Get-NameFromResourceId $searchServiceId
$storageAccountName = Get-NameFromResourceId $storageAccountId
$logicAppName = Get-NameFromResourceId $logicAppId
$aiMainId = $null
if ($tf.PSObject.Properties.Name -contains "ai_services_admin_id") {
  $aiMainId = $tf.ai_services_admin_id.value
}

$logicLocation = az resource show --ids $logicAppId --query location -o tsv
$searchEndpoint = "https://$searchServiceName.search.windows.net"

Write-Info "Resource Group: $ResourceGroupName"
Write-Info "Search Service: $searchServiceName"
Write-Info "Storage Account: $storageAccountName"
Write-Info "Logic App: $logicAppName"

if (-not $SkipRbac) {
  Write-Step "Ensuring RBAC role assignments"

  $logicPrincipalId = az resource show --ids $logicAppId --api-version 2019-05-01 --query identity.principalId -o tsv
  $searchPrincipalId = az resource show --ids $searchServiceId --api-version 2024-03-01-preview --query identity.principalId -o tsv

  if ([string]::IsNullOrWhiteSpace($searchPrincipalId)) {
    throw "Search service managed identity principalId is empty. Cannot assign storage access for indexer."
  }

  Ensure-RoleAssignment -PrincipalId $logicPrincipalId -PrincipalType "ServicePrincipal" -RoleName "Storage Blob Data Contributor" -Scope $storageAccountId
  Ensure-RoleAssignment -PrincipalId $searchPrincipalId -PrincipalType "ServicePrincipal" -RoleName "Storage Blob Data Contributor" -Scope $storageAccountId

  $aiAccounts = az resource list -g $ResourceGroupName --resource-type "Microsoft.CognitiveServices/accounts" --query "[].id" -o tsv
  foreach ($aiId in ($aiAccounts -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
    Ensure-RoleAssignment -PrincipalId $searchPrincipalId -PrincipalType "ServicePrincipal" -RoleName "Cognitive Services User" -Scope $aiId
  }

  $currentUserId = az ad signed-in-user show --query id -o tsv 2>$null
  if (-not [string]::IsNullOrWhiteSpace($currentUserId)) {
    Ensure-RoleAssignment -PrincipalId $currentUserId -PrincipalType "User" -RoleName "Storage Blob Data Contributor" -Scope $storageAccountId
  }
  else {
    Write-WarnLine "Could not resolve signed-in user object id. If Blob connector auth fails, assign Storage Blob Data Contributor manually."
  }
}
else {
  Write-Info "Skipping RBAC role assignments."
}

if (-not $SkipRbac -and -not $SkipSearchObjects) {
  Write-Info "Waiting 60 seconds for RBAC propagation before configuring Search objects..."
  Start-Sleep -Seconds 60
}

if (-not $SkipFoundryProject) {
  Write-Step "Attempting Foundry project creation"

  if ([string]::IsNullOrWhiteSpace($AdminAiAccountName)) {
    $candidateNames = az resource list -g $ResourceGroupName --resource-type "Microsoft.CognitiveServices/accounts" --query "[].name" -o tsv
    $nameList = $candidateNames -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $adminMatch = $nameList | Where-Object { $_ -match "^admin-" } | Select-Object -First 1
    if ($adminMatch) {
      $AdminAiAccountName = $adminMatch
    }
    elseif ($nameList.Count -eq 1) {
      $AdminAiAccountName = $nameList[0]
    }
  }

  if ([string]::IsNullOrWhiteSpace($AdminAiAccountName)) {
    Write-WarnLine "Could not infer admin AI account name. Re-run with -AdminAiAccountName <name> if you want to create a Foundry project."
  }
  else {
    $adminAiId = az resource show -g $ResourceGroupName -n $AdminAiAccountName --resource-type "Microsoft.CognitiveServices/accounts" --query id -o tsv
    $accountUri = "https://management.azure.com${adminAiId}?api-version=2025-04-01-preview"
    $account = az rest --method GET --uri $accountUri | ConvertFrom-Json

    if (-not $account.properties.allowProjectManagement) {
      if ($SkipEnableAllowProjectManagement) {
        Write-WarnLine "allowProjectManagement is false on '$AdminAiAccountName'. Project creation will fail until that is enabled."
        Write-WarnLine "Re-run without -SkipEnableAllowProjectManagement to auto-enable it, or enable it via ARM/Bicep."
      }
      else {
        Write-Info "allowProjectManagement is false. Attempting to enable it on '$AdminAiAccountName'..."
        $tmpEnable = [System.IO.Path]::GetTempFileName()
        try {
          (@{ properties = @{ allowProjectManagement = $true } } | ConvertTo-Json -Depth 6) | Set-Content -Path $tmpEnable -Encoding utf8
          Invoke-AzRestChecked -Method "PATCH" -Uri $accountUri -Resource "" -BodyFile $tmpEnable -MaxAttempts 2 -DelaySeconds 5
          Start-Sleep -Seconds 10
          $account = az rest --method GET --uri $accountUri | ConvertFrom-Json
        }
        catch {
          Write-WarnLine "Failed to enable allowProjectManagement automatically. Details: $($_.Exception.Message)"
        }
        finally {
          Remove-Item -Path $tmpEnable -ErrorAction SilentlyContinue
        }

        if ($account.properties.allowProjectManagement) {
          Write-Ok "allowProjectManagement enabled on '$AdminAiAccountName'."
        }
        else {
          Write-WarnLine "allowProjectManagement is still false. Foundry project creation will be skipped."
        }
      }
    }

    if ($account.properties.allowProjectManagement) {
      $projectUri = "https://management.azure.com${adminAiId}/projects/${ProjectName}?api-version=2025-04-01-preview"
      $projectBody = @{
        location = $account.location
        identity = @{ type = "SystemAssigned" }
        properties = @{
          displayName = $ProjectName
          description = "Created by post_deploy script"
        }
      }

      $tmpProject = [System.IO.Path]::GetTempFileName()
      try {
        $projectBody | ConvertTo-Json -Depth 10 | Set-Content -Path $tmpProject -Encoding utf8
        az rest --method PUT --uri $projectUri --headers "Content-Type=application/json" --body "@$tmpProject" --only-show-errors | Out-Null
        Write-Ok "Foundry project ensured: $ProjectName"
      }
      catch {
        Write-WarnLine "Project creation call failed. Details: $($_.Exception.Message)"
      }
      finally {
        Remove-Item -Path $tmpProject -ErrorAction SilentlyContinue
      }
    }
  }
}
else {
  Write-Info "Skipping Foundry project creation."
}

if (-not $SkipSearchObjects) {
  Write-Step "Configuring AI Search objects (datasource/index/indexer)"

  $apiVersion = $SearchApiVersion

  $effectiveIndexName = $IndexName
  $effectiveSkillsetName = $SkillsetName
  $effectiveDataSourceName = $DataSourceName
  $effectiveIndexerName = $IndexerName

  $existingIndexRaw = az rest --method GET --uri "$searchEndpoint/indexes/${IndexName}?api-version=${apiVersion}" --resource "https://search.azure.com" --only-show-errors 2>$null
  if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($existingIndexRaw)) {
    $existingIndex = $existingIndexRaw | ConvertFrom-Json

    $existingFieldNames = @($existingIndex.fields | ForEach-Object { $_.name })
    $requiredFields = @("chunk_id", "parent_id", "chunk", "text_vector")
    $missing = @($requiredFields | Where-Object { $existingFieldNames -notcontains $_ })

    $textVectorField = $existingIndex.fields | Where-Object { $_.name -eq "text_vector" } | Select-Object -First 1
    $hasVectorFieldConfig = $null -ne $textVectorField -and $null -ne $textVectorField.dimensions -and -not [string]::IsNullOrWhiteSpace($textVectorField.vectorSearchProfile)

    $indexCompatible = ($missing.Count -eq 0) -and $hasVectorFieldConfig

    if (-not $indexCompatible) {
      if ($DisableAutoVersionOnIncompatibleIndex) {
        throw "Existing index '${IndexName}' is incompatible with vector/skillset schema and auto-versioning is disabled."
      }

      $effectiveIndexName = "${IndexName}-${VersionSuffix}"
      $effectiveSkillsetName = "${SkillsetName}-${VersionSuffix}"
      $effectiveDataSourceName = "${DataSourceName}-${VersionSuffix}"
      $effectiveIndexerName = "${IndexerName}-${VersionSuffix}"

      Write-WarnLine "Existing index '${IndexName}' is incompatible (missing/legacy fields)."
      Write-WarnLine "Using versioned names: index=$effectiveIndexName, skillset=$effectiveSkillsetName, datasource=$effectiveDataSourceName, indexer=$effectiveIndexerName"
    }
    else {
      Write-Info "Existing index '${IndexName}' is compatible; reusing configured names."
    }
  }

  $dataSourceBody = @{
    name = $effectiveDataSourceName
    type = "azureblob"
    credentials = @{
      connectionString = "ResourceId=$storageAccountId;"
    }
    container = @{
      name = $BlobContainerName
    }
  }

  $indexBody = @{
    name = $effectiveIndexName
    fields = @(
      @{ name = "chunk_id"; type = "Edm.String"; key = $true; searchable = $true; filterable = $true; sortable = $false; facetable = $false; analyzer = "keyword" },
      @{ name = "parent_id"; type = "Edm.String"; searchable = $false; filterable = $true; sortable = $false; facetable = $false },
      @{ name = "chunk"; type = "Edm.String"; searchable = $true; filterable = $false; sortable = $false; facetable = $false },
      @{ name = "title"; type = "Edm.String"; searchable = $true; filterable = $true; sortable = $true; facetable = $false },
      @{ name = "text_vector"; type = "Collection(Edm.Single)"; searchable = $true; filterable = $false; sortable = $false; facetable = $false; dimensions = 3072; vectorSearchProfile = "text-vector-profile" }
    )
    vectorSearch = @{
      algorithms = @(
        @{ name = "hnsw-config"; kind = "hnsw"; hnswParameters = @{ metric = "cosine" } }
      )
      profiles = @(
        @{ name = "text-vector-profile"; algorithm = "hnsw-config" }
      )
    }
  }

  $skillsetTemplateResolved = $SkillsetTemplatePath
  if (-not [System.IO.Path]::IsPathRooted($skillsetTemplateResolved)) {
    $skillsetTemplateResolved = (Resolve-Path -Path (Join-Path $PSScriptRoot $SkillsetTemplatePath)).Path
  }

  if (-not (Test-Path -Path $skillsetTemplateResolved)) {
    throw "Skillset template not found: $skillsetTemplateResolved"
  }

  $indexerTemplateResolved = $IndexerTemplatePath
  if (-not [System.IO.Path]::IsPathRooted($indexerTemplateResolved)) {
    $indexerTemplateResolved = (Resolve-Path -Path (Join-Path $PSScriptRoot $IndexerTemplatePath)).Path
  }

  if (-not (Test-Path -Path $indexerTemplateResolved)) {
    throw "Indexer template not found: $indexerTemplateResolved"
  }

  if ([string]::IsNullOrWhiteSpace($aiMainId)) {
    $candidateMainAi = az resource list -g $ResourceGroupName --resource-type "Microsoft.CognitiveServices/accounts" --query "[?contains(name, '-ai-')].id | [0]" -o tsv
    if (-not [string]::IsNullOrWhiteSpace($candidateMainAi)) {
      $aiMainId = $candidateMainAi
    }
  }

  if ([string]::IsNullOrWhiteSpace($aiMainId)) {
    throw "Could not determine main AI Services account id for skillset endpoint templating."
  }

  $aiMainName = Get-NameFromResourceId $aiMainId
  $openAiResourceUri = "https://${aiMainName}.openai.azure.com"
  $cognitiveSubdomainUrl = "https://${aiMainName}.cognitiveservices.azure.com/"

  Ensure-AiDeployment `
    -ResourceGroupName $ResourceGroupName `
    -AccountName $aiMainName `
    -DeploymentName $EmbeddingDeploymentName `
    -ModelName $EmbeddingModelName `
    -ModelVersion $EmbeddingModelVersion `
    -SkuName $EmbeddingDeploymentSkuName `
    -Capacity $EmbeddingDeploymentCapacity

  $skillsetBody = Get-Content -Path $skillsetTemplateResolved -Raw | ConvertFrom-Json
  $skillsetBody.PSObject.Properties.Remove("@odata.etag") | Out-Null
  $skillsetBody.name = $effectiveSkillsetName

  foreach ($skill in $skillsetBody.skills) {
    $typeProp = $skill.PSObject.Properties["@odata.type"]
    if ($null -ne $typeProp -and $typeProp.Value -eq "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill") {
      $skill.resourceUri = $openAiResourceUri
      $skill.deploymentId = $EmbeddingDeploymentName
      $skill.modelName = $EmbeddingDeploymentName
    }
  }

  if ($null -ne $skillsetBody.cognitiveServices) {
    $skillsetBody.cognitiveServices.subdomainUrl = $cognitiveSubdomainUrl
  }

  if ($null -ne $skillsetBody.indexProjections -and $null -ne $skillsetBody.indexProjections.selectors) {
    foreach ($selector in $skillsetBody.indexProjections.selectors) {
      $selector.targetIndexName = $effectiveIndexName
    }
  }

  $indexerBody = Get-Content -Path $indexerTemplateResolved -Raw | ConvertFrom-Json
  $indexerBody.PSObject.Properties.Remove("@odata.context") | Out-Null
  $indexerBody.PSObject.Properties.Remove("@odata.etag") | Out-Null
  $indexerBody.PSObject.Properties.Remove("cache") | Out-Null
  $indexerBody.PSObject.Properties.Remove("encryptionKey") | Out-Null
  $indexerBody.name = $effectiveIndexerName
  $indexerBody.dataSourceName = $effectiveDataSourceName
  $indexerBody.skillsetName = $effectiveSkillsetName
  $indexerBody.targetIndexName = $effectiveIndexName

  if ($null -eq $indexerBody.parameters) {
    $indexerBody | Add-Member -NotePropertyName parameters -NotePropertyValue (@{})
  }
  if ($null -eq $indexerBody.parameters.configuration) {
    $indexerBody.parameters | Add-Member -NotePropertyName configuration -NotePropertyValue (@{})
  }
  $indexerBody.parameters.configuration.parsingMode = "default"
  $indexerBody.parameters.configuration.allowSkillsetToReadFileData = $true

  Ensure-StorageContainer -AccountName $storageAccountName -ContainerName $BlobContainerName

  Invoke-SearchPut -Uri "$searchEndpoint/datasources/${effectiveDataSourceName}?api-version=${apiVersion}" -Body $dataSourceBody -MaxAttempts 6 -DelaySeconds 20
  Write-Ok "Data source ensured: $effectiveDataSourceName"

  Invoke-SearchPut -Uri "$searchEndpoint/indexes/${effectiveIndexName}?api-version=${apiVersion}" -Body $indexBody
  Write-Ok "Index ensured: $effectiveIndexName"

  $skillsetApiCandidates = @($SkillsetApiVersion, "2025-11-01-Preview", "2025-11-01") | Select-Object -Unique
  $skillsetCreated = $false
  $skillsetLastError = $null

  foreach ($skillsetApi in $skillsetApiCandidates) {
    try {
      Invoke-SearchPut -Uri "$searchEndpoint/skillsets/${effectiveSkillsetName}?api-version=${skillsetApi}" -Body $skillsetBody
      Write-Ok "Skillset ensured: $effectiveSkillsetName (api-version $skillsetApi)"
      $skillsetCreated = $true
      break
    }
    catch {
      $skillsetLastError = $_
      Write-WarnLine "Skillset create failed with api-version $skillsetApi. Trying next candidate if available."
    }
  }

  if (-not $skillsetCreated) {
    throw "Skillset creation failed across API candidates: $($skillsetApiCandidates -join ', '). Last error: $($skillsetLastError.Exception.Message)"
  }

  Invoke-SearchPut -Uri "$searchEndpoint/indexers/${effectiveIndexerName}?api-version=${apiVersion}" -Body $indexerBody -MaxAttempts 4 -DelaySeconds 30
  Write-Ok "Indexer ensured: $effectiveIndexerName"

  Invoke-AzRestChecked -Method "POST" -Uri "$searchEndpoint/indexers/${effectiveIndexerName}/run?api-version=${apiVersion}" -Resource "https://search.azure.com" -BodyFile ""
  Write-Ok "Indexer run started: $effectiveIndexerName"
}
else {
  Write-Info "Skipping AI Search object configuration."
}

Write-Step "Manual steps (still required)"
$sharepointConn = az resource list -g $ResourceGroupName --resource-type "Microsoft.Web/connections" --query "[?contains(name, 'sharepoint')].name | [0]" -o tsv
if (-not [string]::IsNullOrWhiteSpace($sharepointConn)) {
  Write-Host "1) Authorize SharePoint OAuth:" -ForegroundColor Yellow
  Write-Host "   az resource invoke-action --resource-group $ResourceGroupName --resource-type Microsoft.Web/connections --name $sharepointConn --action consentLink --api-version 2016-06-01"
}
else {
  Write-WarnLine "Could not automatically locate SharePoint connection name."
}

Write-Host "2) Enable Logic App after connector authorization:" -ForegroundColor Yellow
Write-Host "   az logic workflow update --resource-group $ResourceGroupName --name $logicAppName --state Enabled"

Write-Step "Done"
Write-Ok "Post-deploy automation completed."
