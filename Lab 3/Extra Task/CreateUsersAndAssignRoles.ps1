######################## Parameters ########################
param (
    [string]$SqlServerInstanceName = "192.168.137.4\VM3_1",
    [string]$CsvUsersFilePath = "$PSScriptRoot\Users.csv",
    [string]$UserDatabase = "AdventureWorks",
    [bool]$AllowEncryption = $false
)

######################## Commonly Used Variables And Functions ########################
$credentials = Get-Credential -Credential sa
$systemDatabases = "master", "msdb", "model", "tempdb"
[string[]]$allDatabases = $systemDatabases + $UserDatabase

function ExecuteSql([string]$dbName, [string]$query){
    if ([string]::IsNullOrEmpty($dbName)) {
        Invoke-Sqlcmd -ServerInstance $sqlServerInstanceName -Credential $credentials -Query $query -Verbose -ErrorAction Stop
    }
    else {
        Invoke-Sqlcmd -ServerInstance $sqlServerInstanceName -Credential $credentials -Database $dbName -Query $query -Verbose -ErrorAction Stop
    }
}

function ExecuteSqls([string]$dbName, [string[]]$queries){
    $queries | ForEach-Object {ExecuteSql -dbName $dbName -query $_}
}

function DropLoginAndUsersBy([string]$loginName){
    Write-Host "Drop of login and users with name '$loginName' is in progress"
    
    # If user is logged in, kill corresponding process to be able to drop the user furtherly
    (ExecuteSql -dbName "master" -query "SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = '$loginName'") | 
        ForEach-Object {
            $id = [string]$_["session_id"]
            if(![string]::IsNullOrEmpty($id)) { ExecuteSql -dbName "master" -query "KILL $id"}
        }

    $dropLoginQuery = "IF EXISTS (SELECT * FROM master.dbo.syslogins WHERE loginname = '$loginName') DROP LOGIN $loginName"
    ExecuteSql -dbName "master" -query $dropLoginQuery
    
    $dropUserQuery = "IF EXISTS (SELECT * FROM sys.database_principals WHERE name = '$loginName') DROP USER $loginName"
    $allDatabases | ForEach-Object { ExecuteSql -dbName $_ -query $dropUserQuery }
}

function CreateLoginAndUsersBy([string]$loginName, [string]$loginPassword){
    Write-Host "Create of login and users with name '$loginName' is in progress"
    
    $createLoginQuery = "CREATE LOGIN $loginName WITH PASSWORD = '$loginPassword', CHECK_POLICY = OFF"
    ExecuteSql -dbName "master" -query $createLoginQuery    

    $createUserQuery = "CREATE USER $loginName FOR LOGIN $loginName"
    $allDatabases | ForEach-Object { ExecuteSql -dbName $_ -query $createUserQuery }
}

function AssignDbRolesToUser([string[]]$dbRoles, [string]$user, [string]$dbName){
    $queries = $dbRoles | ForEach-Object {"ALTER ROLE $_ ADD MEMBER $user"}
    ExecuteSqls -dbName $dbName -queries $queries
}

function GrantPermissionsToUser([string[]]$permissions, [string]$user, [string]$dbName){
    $queries = $permissions | ForEach-Object {"GRANT $_ TO $user"}
    ExecuteSqls -dbName $dbName -queries $queries
}

function RestrictAccessToSystemDbs([string]$loginName){
    # If 'db_denydatareader' role is assigned to user of'master'/'msdb' tables, it will result in errors while trying to perform login or select from any table
    "master", "msdb" | ForEach-Object {AssignDbRolesToUser -dbRoles "db_denydatawriter" -user $loginName -dbName $_}

    $systemDatabases | ForEach-Object { 
        if($_ -ne "master" -and $_ -ne "msdb") { 
            AssignDbRolesToUser -dbRoles ("db_denydatareader", "db_denydatawriter") -user $loginName -dbName $_ 
        } 
    }
}

######################## User Flow Functions ########################

function RunDevUserFlow([string]$loginName) {
    Write-Host "Running 'dev' flow for user '$loginName'"
    
    # No access to System DBs
    RestrictAccessToSystemDbs -loginName $loginName

    # Read and write the database data of User DB
    AssignDbRolesToUser -dbRoles "db_datareader" -user $loginName -dbName $UserDatabase
    GrantPermissionsToUser -permissions "INSERT" -user $loginName -dbName $UserDatabase
}

function RunApplicationServiceFlow([string]$loginName) {
    Write-Host "Running 'appservice' flow for user '$loginName'"
    
    # No access to System DBs
    RestrictAccessToSystemDbs -loginName $loginName
 
    # Read/write/update the database data of User DB
    AssignDbRolesToUser -dbRoles "db_datareader" -user $loginName -dbName $UserDatabase
    GrantPermissionsToUser -permissions ("INSERT", "UPDATE") -user $loginName -dbName $UserDatabase
}

function RunServiceAccountFlow([string]$loginName) {
    Write-Host "Running 'service' flow for user '$loginName'"

    # Read systems DB
    $systemDatabases | ForEach-Object { AssignDbRolesToUser -dbRoles "db_datareader" -user $loginName -dbName $_ }
 
    # Modify user DB, create backups, but do not delete DB
    AssignDbRolesToUser -dbRoles "db_backupoperator" -user $loginName -dbName $UserDatabase
    GrantPermissionsToUser -permissions ("INSERT", "UPDATE") -user $loginName -dbName $UserDatabase
}

function RunBackupUserFlow([string]$loginName) {
    Write-Host "Running 'backup' flow for user '$loginName'"
    
    # Make backups of all DB
    $allDatabases | ForEach-Object { AssignDbRolesToUser -dbRoles "db_backupoperator" -user $loginName -dbName $_ }

    # Cannot read data from User DB
    AssignDbRolesToUser -dbRoles "db_denydatareader" -user $loginName -dbName $UserDatabase 
}

function RunQaUserFlow([string]$loginName) {
    Write-Host "Running 'qa' flow for user '$loginName'"
    
    # Can only read data from user DB
    AssignDbRolesToUser -dbRoles "db_datareader" -user $loginName -dbName $UserDatabase
}

######################## Execution of Full Scenario ########################

$csvRows = Import-Csv -Path $CsvUsersFilePath

$csvRows | ForEach-Object {
    [string]$role = $_.Role
    [string]$user = $_.User
    [string]$password = $_.Password

    DropLoginAndUsersBy -loginName $user -dbNamesList $allDatabases
    CreateLoginAndUsersBy -loginName $user -loginPassword $password -dbNamesList $allDatabases

    switch ($role) {
        "dev" { RunDevUserFlow -loginName $user }
        "appservice" { RunApplicationServiceFlow -loginName $user }
        "service" { RunServiceAccountFlow -loginName $user }
        "backup" { RunBackupUserFlow -loginName $user }
        "qa" { RunQaUserFlow -loginName $user }

        Default { 
            Write-Host "`nTerminating flow for user '$user', as the role '$role' is not supported.`nSupported roles are: dev, appservice, service, backup, qa"
        }
    }

    Write-Host
}

# Encrypt user database
if ($AllowEncryption){
    Write-Host "Encrypting DB '$UserDatabase'"

    $session = New-PSSession -Credential Administrator -ComputerName "WIN-GP1ELIHAU5V"
    $certificateName = "$($UserDatabase)_Certificate"

    # Create folder for encryption items on remote machine, if necessary
    $folderCreatorScript = {
        if(!(Test-Path -Path "F:\Encryption" -PathType Container)){
            New-Item -Path "F:\Encryption" -ItemType Directory
        }
    }

    Invoke-Command -Session $session -ScriptBlock $folderCreatorScript
    
    $encryptionItemsFolder = "F:\Encryption"
    $certificateFileName = "$encryptionItemsFolder\$certificateName.cer"
    $certificateKeyName = "$encryptionItemsFolder\$certificateName.key"

    $masterKeyPassword = 'Test$2020'
    $certificatePrivateKey = 'TestKey$2020'
    $encryptDbQuery = "
        -- Creating DMK in the 'master' DB
        USE master;
        CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$masterKeyPassword';

        -- Creating certificate in the 'master' DB
        CREATE CERTIFICATE $certificateName WITH SUBJECT = 'DEK_Certificate';

        -- Backup certificate and its private key
        BACKUP CERTIFICATE $certificateName TO FILE = '$certificateFileName'
        WITH PRIVATE KEY
        (FILE = '$certificateKeyName',
        ENCRYPTION BY PASSWORD = '$certificatePrivateKey');

        -- Creating database encryption key
        USE $UserDatabase;
        CREATE DATABASE ENCRYPTION KEY
        WITH ALGORITHM = AES_128
        ENCRYPTION BY SERVER CERTIFICATE $certificateName;

        -- Enabling encryption for the DB
        ALTER DATABASE $UserDatabase
        SET ENCRYPTION ON;"
        
    ExecuteSql -query $encryptDbQuery

    # Check encryption result
    $encryptionCheckQuery = "SELECT is_encrypted FROM sys.databases WHERE name = '$UserDatabase'"
    Write-Host "Checking encryption of '$UserDatabase' DB with query:`n`t$encryptionCheckQuery"
    [bool]$isUserDbEncrypted = (ExecuteSql -dbName "master" -query $encryptionCheckQuery)["is_encrypted"]
    Write-Host "`n'$UserDatabase' DB is encrypted: $isUserDbEncrypted"
}