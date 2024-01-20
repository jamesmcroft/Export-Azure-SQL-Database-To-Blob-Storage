# Export Azure SQL Databases To Blob Storage

You should use this runbook if you want to backup Azure SQL databases to Blob storage using a managed identity.

A `.bacpac` file will be created for each database and stored in the specified Azure Storage blob container on every run of the runbook. The runbook will also delete any `.bacpac` files older than the specified retention period.

The files created will be named in the following format: `databaseName-yyyyMMddHHmm.bacpac`.

## Prerequisites

You will need to update the RBAC permissions of the system assigned managed identity in your Azure Automation account.
Alternatively, create a user assigned managed identity and assign it to the Azure Automation account also.

The following permissions are required for the managed identity:

- DevTest Labs User [Scope: Resource Group]
- Reader [Scope: Resource Group]
- Contributor [Scope: Azure SQL Server]
- Storage Blob Data Contributor [Scope: Storage Account]

If you are using a user assigned managed identity, the system assigned managed identity will need the first two permissions.

For more information on how to configure managed identity with runbooks, see [this tutorial on Microsoft Docs](https://learn.microsoft.com/en-us/azure/automation/learn/powershell-runbook-managed-identity)

> Note: This runbook can be used together with Azure SQL database backups.

## Parameters

- **ResourceGroupName**: The name of the resource group where the Azure resources are located.
- **ManagedIdentityType**: The type of managed identity to use. Valid values are `System` and `User`.
- **UserIdentityName**: The name of the user assigned managed identity to use. This parameter must be set if the ManagedIdentityType parameter is set to `User`.
- **SqlServerName**: The name of the Azure SQL Server.
- **SqlServerAdmin**: The username of the Azure SQL Server administrator.
- **SqlServerAdminPw**: The password of the Azure SQL Server administrator.
- **DatabaseNames**: A comma separated list of the names of the Azure SQL databases to backup.
- **StorageAccountName**: The name of the Azure Storage account where the backups will be stored.
- **StorageAccountKey**: The access key of the Azure Storage account where the backups will be stored. To locate this value, follow the instructions in [this Microsoft Docs article](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-keys-manage?tabs=azure-portal#view-account-access-keys)
- **BlobContainerName**: The name of the Azure Storage blob container where the backups will be stored. If the blob container does not exist, it will be created.
- **RetentionDays**: The number of days to keep the backups in the Azure Storage blob container.
