-- Create tables for contract analysis storage in Azure SQL Database
-- Run this script as the Azure AD admin after creating the database

-- Contracts table
CREATE TABLE contracts (
    id INT IDENTITY(1,1) PRIMARY KEY,
    filename NVARCHAR(500),
    title NVARCHAR(1000),
    duration NVARCHAR(500),
    jurisdictions NVARCHAR(MAX),  -- JSON array
    dates NVARCHAR(MAX),          -- JSON object
    markdown NVARCHAR(MAX),
    raw_fields NVARCHAR(MAX),     -- JSON object
    created_at DATETIME2 DEFAULT GETUTCDATE()
);

-- Parties table
CREATE TABLE parties (
    id INT IDENTITY(1,1) PRIMARY KEY,
    contract_id INT NOT NULL,
    name NVARCHAR(500),
    address NVARCHAR(1000),
    reference_name NVARCHAR(500),
    clause NVARCHAR(MAX),
    FOREIGN KEY (contract_id) REFERENCES contracts(id) ON DELETE CASCADE
);

-- Clauses table
CREATE TABLE clauses (
    id INT IDENTITY(1,1) PRIMARY KEY,
    contract_id INT NOT NULL,
    clause_type NVARCHAR(200),
    title NVARCHAR(500),
    text NVARCHAR(MAX),
    FOREIGN KEY (contract_id) REFERENCES contracts(id) ON DELETE CASCADE
);

-- Indexes for common queries
CREATE INDEX IX_parties_contract_id ON parties(contract_id);
CREATE INDEX IX_clauses_contract_id ON clauses(contract_id);
CREATE INDEX IX_contracts_created_at ON contracts(created_at);

-- ============================================================================
-- Grant permissions to the Function App's Managed Identity
-- Replace <function-app-name> with your actual Function App name
-- ============================================================================

-- First, create the user from the managed identity
-- CREATE USER [<function-app-name>] FROM EXTERNAL PROVIDER;

-- -- Grant read/write permissions
-- ALTER ROLE db_datareader ADD MEMBER [<function-app-name>];
-- ALTER ROLE db_datawriter ADD MEMBER [<function-app-name>];
