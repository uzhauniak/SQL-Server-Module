[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]
    $InstanceName,

    [Parameter(Mandatory=$true)]
    [string]
    $SaUserPassword,

    [string]
    $SqlServerIsoPath="E:\SQLServer2014SP3-FullSlipstream-x64-ENU.iso"
)

# Import sqlserver and netsecurity modules
Import-Module NetSecurity

# Check whether base configuration file exists
$configurationFilePath = ".\ConfigurationFile_Install.ini"
if(!(Get-Item -Path $configurationFilePath).Exists){
    throw "Base configuration file is not found. Navigate to the script directory and run it again."
}

# Prepare configuration file provided
$configurationFileContent = Get-Content -Path $configurationFilePath

$configurationFileContent = $configurationFileContent -replace '(instancename=).*', "`$1`"$InstanceName`""
$configurationFileContent = $configurationFileContent -replace '(instanceid=).*', "`$1`"$InstanceName`""

$configurationFileContent = $configurationFileContent -replace '(agtsvcaccount=).*', "`$1`"NT Service\SQLAgent`$$InstanceName`""
$configurationFileContent = $configurationFileContent -replace '(sqlsvcaccount=).*', "`$1`"NT Service\MSSQL`$$InstanceName`""

$administratorAccountName = (Get-LocalGroupMember -Group "Administrators")[0].Name
$configurationFileContent = $configurationFileContent -replace '(sqlsysadminaccounts=).*', "`$1`"$administratorAccountName`""

$configurationFileContent = $configurationFileContent -replace '(sqlbackupdir=).*', "`$1`"E:\Microsoft SQL Server\MSSQL12.$InstanceName\MSSQL\Backup`""
$configurationFileContent = $configurationFileContent -replace '(sapwd=).*', "`$1`"$SaUserPassword`""

Set-Content -Path $configurationFilePath -Value $configurationFileContent

# Run SQL Server Setup executable using temp configuration file and show installed features
$sqlServerSetupExecutable = "$((Mount-DiskImage -ImagePath $SqlServerIsoPath | Get-Volume).DriveLetter):\setup.exe"
try {
    Write-Host "`nInstallation is started"
    Start-Process -FilePath $sqlServerSetupExecutable -ArgumentList "/ConfigurationFile=$configurationFilePath" -Wait
}
catch [InvalidOperationException] {
    throw "SQL Server Setup executable can not be found by provided path"
}

Write-Host "Installation is Finished"

# Generate Feature Discovery Report and dismount SQL Server ISO image
Write-Host "Feature Discovery Report generation is started"
Start-Process -FilePath $sqlServerSetupExecutable -ArgumentList "/Action=RunDiscovery /q" -Wait
$logFolderPath = (Get-ChildItem "$Env:Programfiles\Microsoft SQL Server\120\Setup Bootstrap\Log" | Sort-Object -Property CreationTime -Descending | Select-Object -First 1).FullName
Invoke-Item -Path "$logFolderPath\SqlDiscoveryReport.htm"
Write-Host "Feature Discovery Report generation is finished"

Dismount-DiskImage -ImagePath $SqlServerIsoPath | Out-Null

# Get dynamically assigned port of SQL Server Named Instance from registry
$instanceNetInfoRegistryPath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL12.$InstanceName\MSSQLServer\SuperSocketNetLib\Tcp\IPAll"
$instancePort = (Get-ItemProperty -Path $instanceNetInfoRegistryPath).TcpDynamicPorts

# Create Firewall Inbound rules for SQL Server Named Instance, SQL Server Browser
$sqlServerInstanceRule = New-NetFirewallRule -DisplayName "SQL Server Named Instance Connection - $InstanceName" -Direction Inbound -Protocol TCP -LocalPort $instancePort -Action Allow

$sqlServerBrowserRule = Get-NetFirewallRule -DisplayName "SQL Server Browser Connection" -ErrorAction SilentlyContinue
if($null -eq $sqlServerBrowserRule){
    $sqlServerBrowserRule = (New-NetFirewallRule -DisplayName "SQL Server Browser Connection" -Direction Inbound -Protocol UDP -LocalPort 1434 -Action Allow)
}


# Enable RDP and appropriate firewall rules
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name "fDenyTSConnections" -value 0
$rdpRulesGroup = Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -PassThru

# Show computer and installed SQL Server instance names
Write-Host ("`nComputer Name: {0}" -f ((Get-WmiObject -Class Win32_ComputerSystem).Name))
Write-Host ("SQL Server Instance Name: {0}" -f $InstanceName)

# Show created/enabled Firewall rules
Write-Host "`nCreated Firewall Rules:"
($sqlServerInstanceRule, $sqlServerBrowserRule) | 
    Format-List -Property DisplayName, Direction, Action, 
        @{l="Protocol";e={($_ | Get-NetFirewallPortFilter).Protocol}}, 
        @{l="Local Port";e={($_ | Get-NetFirewallPortFilter).LocalPort}}

Write-Host "`nEnabled Firewall Rules:"
$rdpRulesGroup | 
    Format-List -Property DisplayName, Direction, Action, 
        @{l="Protocol";e={($_ | Get-NetFirewallPortFilter).Protocol}}, 
        @{l="Local Port";e={($_ | Get-NetFirewallPortFilter).LocalPort}}