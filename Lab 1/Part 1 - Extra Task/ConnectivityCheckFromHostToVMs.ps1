Import-Module -Name SqlServer

# Create credential objects for connection to VM1 and VM2 under "sa" user
$credentialsVm1 = Get-Credential sa 
$credentialsVm2 = Get-Credential sa 

# Connect to VMs under "sa" user and execute "SELECT @@SERVERNAME"
Invoke-Sqlcmd -ServerInstance 192.168.137.2 -Credential $credentialsVm1 -Query "SELECT @@SERVERNAME"
Invoke-Sqlcmd -ServerInstance "192.168.137.3\VM2_MSSQLSERVER" -Credential $credentialsVm2 -Query "SELECT @@SERVERNAME"