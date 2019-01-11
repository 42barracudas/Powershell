SET ExecutionPolicy UnRestreicted
#
#Create a Folder to store the DB
#
$currentDirectory = Get-Location
$prefix=Read-Host ?Enter Prefix?
$dirName = "F:\DATA\SQL2008R2\$prefix"
if(-not (test-path $dirName)) {
    md $dirName | out-null
} else {
    write-host "$dirName already exists!"
}
#
#Sources and selection
#
$reportingDB='F:\Databases\iServerReportingDB_2200\*'

Write-Host '1 = TOGAF 9.2'
Write-Host '2 = ArchiMate 3.0'
Write-Host '3 = TOGAF 9.2 + SPM + BPA'
Write-Host '4 = Archimate 3.0 + BPA'
Write-Host '5 = BPA'
Write-Host '6 = TOGAF 9.2 + ALL'
Write-Host '7 = ArchiMate 3.0 + ALL(SABSA)'

#DB ver = 563.00
switch(read-host "Select Database"){
1 {$source = 'F:\Databases\01. TOGAF 9.2\*'}
2 {$source = 'F:\Databases\02. ArchiMate 3.0\*'}
3 {$source = 'F:\Databases\03. TOGAF 9.2 + SPM + BPA\*'}
4 {$source = 'F:\Databases\04. Archimate 3.0 + BPA\*'}
5 {$source = 'F:\Databases\05. BPA\*'}
6 {$source = 'F:\Databases\06. TOGAF 9.2 + ALL\*'}
7 {$source = 'F:\Databases\07. ArchiMate 3.0 + ALL_SABSA\*'}
8 {$source = 'F:\Databases\iServerDB_Cust_v563.00_SQL2008r2_TOGAF (ObjNameUpd-fix)\*'}
9 {$source = 'F:\Databases\Other\*'}
default {$source = 'F:\Databases\01. TOGAF 9.2\*'}
}

Write-Host 'using DB from: '$source


Copy-Item -path $source -destination $dirName -recurse
Copy-Item -path $reportingDB -destination $dirName -recurse

Write-Host 'Done'

#
#Edit config
#

(Get-Content C:\Users\da-vvynohradov\Desktop\Script\DatabasesConfig_template.xml) | ForEach-Object { $_ -replace "XYZ", "$Prefix" } | Set-Content C:\Users\da-vvynohradov\Desktop\Script\DatabasesConfig.xml

#
#  / Run DB attach
#

# if required Run as Administrator
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit }

Set-Location $PSScriptRoot

# Load DB configuration XML file.
[xml]$config = Get-Content "C:\Users\DA-VVynohradov\Desktop\Script\DatabasesConfig.xml"

#Add-Type -AssemblyName "Microsoft.SqlServer.Smo, Version=12.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91"
Add-Type -AssemblyName "Microsoft.SqlServer.Smo, Version=13.0.0.0, Culture=neutral, PublicKeyToken=89845dcd8080cc91"
#[Reflection.Assembly]::LoadWithPartialName( "Microsoft.SqlServer.Smo" ) > $null
$smo = New-Object Microsoft.SqlServer.Management.Smo.Server $config.SQL.Server

try {
    $smo.ConnectionContext.Connect()
} catch {
    try {
        $smo.ConnectionContext.LoginSecure = false
        $smo.ConnectionContext.Login = $config.SQL.Credentials.Login
        $smo.ConnectionContext.Password = $config.SQL.Credentials.Password
        $smo.ConnectionContext.Connect()
    } catch {
        Write-Host "Can't connect to $($config.SQL.Server) as $(whoami)" -ForegroundColor Red
        Write-Host "Can't connect to $($config.SQL.Server) with $($config.SQL.Credentials.Login):$($config.SQL.Credentials.Password)" -ForegroundColor Red

        if ($Host.Name -eq "ConsoleHost")
        {
            Write-Host "Press any key to exit..."
            $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp") > $null
        }
        return
    }
}

ForEach ($database in $config.SQL.Databases.Database)
{
    $mdfFilename = $database.MDF | Resolve-Path
    $ldfFilename = $database.LDF | Resolve-Path
    $DBName = $database.DB_Name

    $files = New-Object System.Collections.Specialized.StringCollection
    $files.Add($mdfFilename) | Out-Null
    $files.Add($ldfFilename) | Out-Null

    try
    {
        Write-Host "Attaching $DBName... " -NoNewline
        $smo.AttachDatabase($DBName, $files, 'sa')
        Write-Host "DONE" -ForegroundColor Green
    } 
    catch [Exception]
    {
        Write-Host "FAILED" -ForegroundColor Red
        echo $_.Exception|format-list -force
    }
}


#
# End of *Run DB Attach*
#

#
# Begin Import AD Group Mapping
#

#import SQL Server module
SET ExecutionPolicy UnRestreicted
Import-Module SQLPS –DisableNameChecking
Import-module sqlascmdlets

$instanceName = "ORB-EMEA-SQL1"
$sqlagentinstance = "ORB-EMEA-SQL1"
$loginName = "ORBUSCLOUD\"+"$prefix"+"Group"
$dbUserName = "ORBUSCLOUD\"+"$prefix"+"Group"
$iServerDB = "$prefix"+"-iServerDB"
$iServerReportingDB = "$prefix"+"-iServerReportingDB"
$roleName = "iServerUsers"
$reportingRole = "iServerReporting"

$server = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $instanceName
# drop login if it exists
if ($server.Logins.Contains($loginName))  
{   
    Write-Host("Deleting the existing login $loginName.")
       $server.Logins[$loginName].Drop() 
}

#$login = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Login -ArgumentList $server, "$loginName"
$login = New-Object Microsoft.SqlServer.Management.Smo.Login($server, $loginName)
$login.LoginType = 'WindowsGroup'
$login.DefaultDatabase = $iServerDB
$login.PasswordPolicyEnforced = $false
$login.Create('')
Write-Host("Login $loginName created successfully.")

    $database = $server.Databases[$iServerDB]
    if ($database.Users[$roleName])
    {
        Write-Host("Dropping user $dbUserName on $database.")
        $database.Users[$roleName].Drop()
    }

    #assign iServerDB role for a new user
    $dbrole = $database.Roles[$roleName]
    $dbrole.AddMember($loginName)
    $dbrole.Alter()
    Write-Host("$loginName successfully added to $roleName role.")
    
    $dbUser = New-Object `
-TypeName Microsoft.SqlServer.Management.Smo.User `
-ArgumentList $database, $dbUserName
$dbUser.Login = $loginName
$dbUser.Create()

    $ReportingDB = $server.Databases[$iServerReportingDB]
    if ($ReportingDB.Users[$reportingRole])
    {
        Write-Host("Dropping user $dbUserName on $database.")
        $ReportingDB.Users[$reportingRole].Drop()
    }

    #assign ReportingDB role for a new user
    $dbrole = $ReportingDB.Roles[$reportingRole]
    $dbrole.AddMember($loginName)
    $dbrole.Alter()
    Write-Host("$loginName successfully added to $reportingRole role.")

     $dbUser = New-Object `
-TypeName Microsoft.SqlServer.Management.Smo.User `
-ArgumentList $ReportingDB, $dbUserName
$dbUser.Login = $loginName
$dbUser.Create()

#Create RS Folder
#PREREQUISITE: Install-Module -Name ReportingServicesTools    
New-RsFolder -ReportServerUri http://ORB-EMEA-SQL1/ReportServer -Path / -Name $prefix'- Reports' -Verbose

#Create Job
(Get-Content C:\Users\DA-VVynohradov\Desktop\Script\create_job_raw.sql) | ForEach-Object { $_ -replace "XYZ", "$Prefix" } | Set-Content C:\Users\DA-VVynohradov\Desktop\Script\create_job_raw_output.sql
    invoke-sqlcmd -inputfile "C:\Users\DA-VVynohradov\Desktop\Script\create_job_raw_output.sql" -serverinstance $sqlagentinstance -database "master"
sleep -seconds 2

#Run Job
[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | out-null
$JobName = "$Prefix-iServer_report_update"
$StepName = 'SSIS'
$jobserver = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Server -ArgumentList $sqlagentinstance
$job = $jobserver.jobserver.jobs["$JobName"]
if ($job)
{	
	if($StepName) 
	{
		$job.Start($StepName)
	}
	else 
	{
		$job.Start()
	}

	Write-host "Job $($JobName) on Server $($sqlagentinstance) started"
	$i = 0
}

# Upgrade DB to 694 (iServer 2019)
#SELECT TOP 1 * FROM [$Prefix-iServerDB].[dbo].[DBVersion] ORDER BY DBVersion DESC
#invoke-sqlcmd -inputfile "C:\Users\DA-VVynohradov\Desktop\Script\v563.00 to v694.00.sql" -serverinstance $instanceName -database $iServerDB
#sleep -seconds 2

#map PortalUser