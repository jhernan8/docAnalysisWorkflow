// ============================================================================
// DAB MCP Server - Parameters
// Fill in values referencing your existing Contract Analysis deployment
// ============================================================================

using 'main.bicep'

// Existing SQL Server name (from infra_sql deployment output: sqlServerFqdn minus .database.windows.net)
param sqlServerName = ''       // e.g., 'contracts-dev-sql-a1b2c3d4'
param sqlDatabaseName = 'contractsdb'

// Existing VNet (same one used by Function App / Logic App)
param vnetName = 'cai-a1-tst-vnet-spoke01'
param vnetResourceGroupName = '' // Resource group containing the VNet

// Container Apps subnet — must not overlap existing subnets, minimum /23
param containerAppSubnetAddressPrefix = '' // e.g., '10.0.8.0/23'

// ACR — created during the DAB quickstart, or create one with deploy.sh
param acrName = '' // e.g., 'acrsqlmcp1234'

// Private DNS Zones (cross-subscription, same as infra_sql deployment)
param dnsZoneSubscriptionId = ''
param dnsZoneResourceGroupName = ''

// Optional overrides
// param location = 'eastus'
// param acrImageName = 'contracts-mcp-server:1'
