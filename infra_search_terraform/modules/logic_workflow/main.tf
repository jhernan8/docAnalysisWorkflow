locals {
  azureblob_managed_api_id    = "/subscriptions/${var.subscription_id}/providers/Microsoft.Web/locations/${var.location}/managedApis/azureblob"
  sharepoint_managed_api_id   = "/subscriptions/${var.subscription_id}/providers/Microsoft.Web/locations/${var.location}/managedApis/sharepointonline"
  blob_connection_id          = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}/providers/Microsoft.Web/connections/${var.blob_connection_name}"
}

resource "azurerm_resource_group_template_deployment" "blob_connection_mi" {
  name                = "${var.blob_connection_name}-mi"
  resource_group_name = var.resource_group_name
  deployment_mode     = "Incremental"

  template_content = jsonencode({
    "$schema" = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"
    parameters = {
      connectionName = { type = "string" }
      location       = { type = "string" }
      displayName    = { type = "string" }
      managedApiId   = { type = "string" }
      tags           = { type = "object" }
    }
    resources = [
      {
        type       = "Microsoft.Web/connections"
        apiVersion = "2016-06-01"
        name       = "[parameters('connectionName')]"
        location   = "[parameters('location')]"
        tags       = "[parameters('tags')]"
        properties = {
          displayName = "[parameters('displayName')]"
          api = {
            id = "[parameters('managedApiId')]"
          }
          parameterValueSet = {
            name   = "managedIdentityAuth"
            values = {}
          }
        }
      }
    ]
  })

  parameters_content = jsonencode({
    connectionName = { value = var.blob_connection_name }
    location       = { value = var.location }
    displayName    = { value = var.blob_connection_display_name }
    managedApiId   = { value = local.azureblob_managed_api_id }
    tags           = { value = var.tags }
  })
}

resource "azurerm_api_connection" "sharepoint" {
  name                = var.sharepoint_connection_name
  display_name        = var.sharepoint_connection_display_name
  managed_api_id      = local.sharepoint_managed_api_id
  resource_group_name = var.resource_group_name
  parameter_values    = {}
  tags                = var.tags
}

resource "azurerm_logic_app_workflow" "this" {
  name                = var.logic_app_name
  location            = var.location
  resource_group_name = var.resource_group_name
  enabled             = true
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }

  parameters = {
    "$connections" = jsonencode({
      azureblob = {
        connectionId   = local.blob_connection_id
        connectionName = var.blob_connection_name
        id             = local.azureblob_managed_api_id
        connectionProperties = {
          authentication = {
            type = "ManagedServiceIdentity"
          }
        }
      }
      sharepointonline = {
        connectionId   = azurerm_api_connection.sharepoint.id
        connectionName = azurerm_api_connection.sharepoint.name
        id             = local.sharepoint_managed_api_id
      }
    })
  }

  depends_on = [
    azurerm_resource_group_template_deployment.blob_connection_mi,
    azurerm_api_connection.sharepoint
  ]

  workflow_parameters = {
    "$connections" = jsonencode({
      defaultValue = {}
      type         = "Object"
    })
  }

  workflow_schema  = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
  workflow_version = "1.0.0.0"
}

resource "azurerm_logic_app_action_custom" "get_file_content" {
  logic_app_id = azurerm_logic_app_workflow.this.id
  name         = "Get_file_content_from_SharePoint"
  body = jsonencode({
    inputs = {
      host = {
        connection = {
          name = "@parameters('$connections')['sharepointonline']['connectionId']"
        }
      }
      method = "get"
      path   = "/datasets/@{encodeURIComponent(encodeURIComponent('${var.sharepoint_site_url}'))}/files/@{encodeURIComponent(triggerBody()?['{Identifier}'])}/content"
      queries = {
        inferContentType = true
      }
    }
    runAfter = {}
    type     = "ApiConnection"
  })
}

resource "azurerm_logic_app_action_custom" "create_blob" {
  logic_app_id = azurerm_logic_app_workflow.this.id
  name         = "Create_blob_in_contracts_container"
  body = jsonencode({
    inputs = {
      body = "@body('Get_file_content_from_SharePoint')"
      headers = {
        ReadFileMetadataFromServer = true
      }
      host = {
        connection = {
          name = "@parameters('$connections')['azureblob']['connectionId']"
        }
      }
      method = "post"
      path   = "/v2/datasets/@{encodeURIComponent(encodeURIComponent('${var.storage_account_name}'))}/files"
      queries = {
        folderPath                   = "/contracts"
        name                         = "@triggerBody()?['{FilenameWithExtension}']"
        queryParametersSingleEncoded = true
      }
    }
    runAfter = {
      Get_file_content_from_SharePoint = ["Succeeded"]
    }
    runtimeConfiguration = {
      contentTransfer = {
        transferMode = "Chunked"
      }
    }
    type = "ApiConnection"
  })
}

resource "azurerm_logic_app_trigger_custom" "sharepoint_new_file" {
  logic_app_id = azurerm_logic_app_workflow.this.id
  name         = "When_a_file_is_created_in_SharePoint"
  body = jsonencode({
    inputs = {
      host = {
        connection = {
          name = "@parameters('$connections')['sharepointonline']['connectionId']"
        }
      }
      method = "get"
      path   = "/datasets/@{encodeURIComponent(encodeURIComponent('${var.sharepoint_site_url}'))}/tables/@{encodeURIComponent(encodeURIComponent('${var.sharepoint_library_id}'))}/onnewfileitems"
    }
    recurrence = {
      frequency = "Minute"
      interval  = 1
    }
    splitOn = "@triggerBody()?['value']"
    type    = "ApiConnection"
  })
}
