<#
.SYNOPSIS
    Automates Azure SQL database backup to Blob storage and deletes old backups from blob storage.
.DESCRIPTION
	You should use this runbook if you want to backup Azure SQL databases to Blob storage using a managed identity.
	This runbook can be used together with Azure SQL database backups.

    If you are using the recommended PowerShell 7.2 runtime version, you will need to install the following module:

    - Az.ManagedServiceIdentity

    You will also need to update the RBAC permissions of the system assigned managed identity in your Azure Automation account.
    Alternatively, create a user assigned managed identity and assign it to the Azure Automation account also.

    The following permissions are required for the managed identity:
    - DevTest Labs User [Scope: Resource Group]
    - Reader [Scope: Resource Group]
    - Contributor [Scope: Azure SQL Server]
    - Storage Blob Data Contributor [Scope: Storage Account]

    If you are using a user assigned managed identity, the system assigned managed identity will need the first two permissions.
.PARAMETER ResourceGroupName
	The name of the resource group where the Azure resources are located.
.PARAMETER ManagedIdentityType
    The type of managed identity to use. Valid values are 'System' and 'User'.
.PARAMETER UserIdentityName
    The name of the user assigned managed identity to use. This parameter must be set if the ManagedIdentityType parameter is set to 'User'.
.PARAMETER SqlServerName
	The name of the Azure SQL Server.
.PARAMETER SqlServerAdmin
    The username of the Azure SQL Server administrator.
.PARAMETER SqlServerAdminPw
    The password of the Azure SQL Server administrator.
.PARAMETER DatabaseNames
    A comma separated list of the names of the Azure SQL databases to backup.
.PARAMETER StorageAccountName
    The name of the Azure Storage account where the backups will be stored.
.PARAMETER StorageAccountKey
    The access key of the Azure Storage account where the backups will be stored.
.PARAMETER BlobContainerName
    The name of the Azure Storage blob container where the backups will be stored.
.PARAMETER RetentionDays
    The number of days to keep the backups in the Azure Storage blob container.
.EXAMPLE
    .\Export-AzureSqlToBlobStorage.ps1 -ResourceGroupName "MyResourceGroup" -ManagedIdentityType "User" -UserIdentityName "MyUserIdentity" -SqlServerName "MySqlServer" -SqlServerAdmin "MySqlServerAdmin" -SqlServerAdminPw "MySqlServerAdminPw" -DatabaseNames "MyDatabase1,MyDatabase2" -StorageAccountName "MyStorageAccount" -StorageAccountKey "MyStorageAccountKey" -BlobContainerName "MyBlobContainer" -RetentionDays 30
.NOTES
    Author: James Croft
    Date: 2024-01-19
#>

param
(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
    [Parameter(Mandatory = $true)]
    [ValidateSet("System", "User")]
    [string]$ManagedIdentityType,
    [Parameter()]
    [string]$UserIdentityName,
    [Parameter(Mandatory = $true)]
    [string]$SqlServerName,
    [Parameter(Mandatory = $true)]
    [string]$SqlServerAdmin,
    [Parameter(Mandatory = $true)]
    [string]$SqlServerAdminPw,
    [Parameter(Mandatory = $true)]
    [string]$DatabaseNames,
    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,
    [Parameter(Mandatory = $true)]
    [string]$StorageAccountKey,
    [Parameter(Mandatory = $true)]
    [string]$BlobContainerName,
    [Parameter(Mandatory = $true)]
    [int]$RetentionDays
)

function Set-AzureAccount($tenantId, $subscriptionId, $resourceGroupName, $managedIdentityType, $userIdentityName) {
    $azureContext = (Connect-AzAccount -Identity).context

    Write-Host "Connecting to Azure in subscription '$($azureContext.Subscription.Name)'"

    $azureContext = Set-AzContext -Subscription $azureContext.Subscription.Name -DefaultProfile $azureContext

    if ($managedIdentityType -eq "System") {
        Write-Host "Connecting to Azure using system assigned managed identity"
    }
    else {
        Write-Host "Connecting to Azure using user assigned managed identity '$userIdentityName'"
        $identity = Get-AzUserAssignedIdentity -ResourceGroupName $resourceGroupName -Name $userIdentityName -DefaultProfile $azureContext
        $azureContext = (Connect-AzAccount -Identity -AccountId $identity.ClientId).context
        $azureContext = Set-AzContext -Subscription $azureContext.Subscription.Name -DefaultProfile $azureContext
    }     
}

function Set-BlobContainer([string]$blobContainerName, $storageContext) {
    Write-Host "Checking if blob container '$blobContainerName' already exists"
    if (Get-AzStorageContainer -Context $storageContext -Name $blobContainerName | Where-Object { $_.Name -eq $blobContainerName }) {
        Write-Host "Blob container '$blobContainerName' already exists"
    }
    else {
        Write-Host "Creating blob container '$blobContainerName'"
        New-AzStorageContainer -Context $storageContext -Name $blobContainerName
    }
}

function Export-SqlDatabaseToBlobContainer([string]$resourceGroupName, [string]$sqlServerName, [string]$sqlServerAdmin, [string]$sqlServerAdminPw, [string]$databaseNames, [string]$storageKey, [string]$storageContainerUri, [string]$blobContainerName) {
    Write-Host "Starting SQL export from '$sqlServerName' for databases '$databaseNames'"

    $securePassword = ConvertTo-SecureString -String $sqlServerAdminPw -AsPlainText -Force 
    $sqlCredentials = New-Object System.Management.Automation.PSCredential ($sqlServerAdmin, $securePassword)

    foreach ($databaseName in $databaseNames.Split(",").Trim()) {
        Write-Host "Starting SQL database export from '$sqlServerName' for database '$databaseName'"

        $bacpacBlobName = $databaseName + (Get-Date).ToString("yyyyMMddHHmm") + ".bacpac"
        $bacpacBlobUri = $storageContainerUri + $blobContainerName + "/" + $bacpacBlobName

        $exportRequest = New-AzSqlDatabaseExport `
            -ResourceGroupName $resourceGroupName `
            -ServerName $sqlServerName `
            -DatabaseName $databaseName `
            -StorageKeyType "StorageAccessKey" `
            -StorageKey $storageKey `
            -StorageUri $bacpacBlobUri `
            -AdministratorLogin $sqlCredentials.UserName `
            -AdministratorLoginPassword $sqlCredentials.Password

        Get-AzSqlDatabaseImportExportStatus -OperationStatusLink $exportRequest.OperationStatusLink
    }
}

function Remove-ExpiredBackups([int]$retentionDays, [string]$blobContainerName, $storageContext) {
    Write-Host "Removing expired backups from blob container '$blobContainerName'"

    $blobs = Get-AzStorageBlob -Container $blobContainerName -Context $storageContext

    foreach ($blob in ($blobs | Where-Object { $_.LastModified.UtcDateTime -lt (Get-Date).AddDays(-$retentionDays) })) {
        Write-Host "Removing expired backup '$($blob.Name)' from blob container '$blobContainerName'"
        Remove-AzStorageBlob -Blob $blob.Name -Container $blobContainerName -Context $storageContext
    }
}

Disable-AzContextAutosave -Scope Process | Out-Null

Write-Host "Starting SQL export"

Set-AzureAccount `
    -resourceGroupName $ResourceGroupName `
    -managedIdentityType $ManagedIdentityType `
    -userIdentityName $UserIdentityName

$StorageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey

Set-BlobContainer `
    -blobContainerName $BlobContainerName `
    -storageContext $StorageContext

Export-SqlDatabaseToBlobContainer `
    -resourceGroupName $ResourceGroupName `
    -sqlServerName $SqlServerName `
    -sqlServerAdmin $SqlServerAdmin `
    -sqlServerAdminPw $SqlServerAdminPw `
    -databaseNames $DatabaseNames `
    -storageKey $StorageAccountKey `
    -storageContainerUri $StorageContext.BlobEndPoint `
    -blobContainerName $BlobContainerName

Remove-ExpiredBackups `
    -retentionDays $RetentionDays `
    -blobContainerName $BlobContainerName `
    -storageContext $StorageContext

Write-Host "SQL export completed"