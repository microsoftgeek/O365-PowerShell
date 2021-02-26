<# 
.SYNOPSIS
    The purpose of this script is to go through all the input Distribution Groups (from output of Get-DLEligibility) and migrate them to a Unified Group.

.DESCRIPTION
    This script must be executed from an admin powershell session with Exchange online

    Copyright (c) Microsoft Corporation. All rights reserved.

   A DL is eligible for migration if it meets all of the below criteria:
        DL is managed on the cloud.
        DL does not have any nested Groups and is not a member of any other group.
        DL is not moderated.
        DL does not have send on behalf set.
        DL is not hidden from address list.
        DL does not have any member types other than UserMailbox, SharedMailbox, TeamMailbox, MailUser, GuestMailUser
        DL is a closed group. --> can be converted to private by specifying an override switch

    If the DL is eligible, then all the properties of the DL are copied onto the Unified Group including SMTP.

.PARAMETER TenantName
    Name of the tenant. For ex: microsoft.com

.PARAMETER Credential
    Admin credentials used to open new sessions

.PARAMETER NoOfConnections
    Maximum number of PS sessions to use. Range: 1-3. Exchange supports a maximum of 3 connections per user.

.PARAMETER ConnectionUri
    Url of the exchange endpoint to connect to from Powershell

.PARAMETER WorkingDir
    Path to the directory where the log files, intermediate file and final output files will be stored.

.PARAMETER DlEligibilityListPath
    Path of the input file having the list of DLs to be migrated. This should be the selected output from Get-DLEligibility.
    
.PARAMETER IsDCAdmin
    When the script is run by a DC Ops, this has to be set as true.

.PARAMETER ContinueFromPrevious
    true - If there is a MigrationOutput file in the working directory, considers only those DLs which are not processed.
    false - Starts migrating all the DLs afresh.

.PARAMETER BatchSize
    The script will process the DLs in batch size provided. After each batch, a status of number of DLs processed will be displayed and a prompt will be made to continue further.

.PARAMETER ConvertClosedDlToPrivateGroup
    true - Migrates a DL with Closed MemberJoinRestriction or MemberDepartRestriction to a private group.
    false - Does not migrate Dl if MemberJoinRestriction or MemberDepartRestriction is closed.

.PARAMETER DeleteDlAfterMigration
    true - The DL is deleted if migration is successful.
    false - The DL is renamed and hiden from GAL, but will be accessible through Cmdlets. 

.EXAMPLE

    .\Convert-DistributionGroupToUnifiedGroup.ps1 -TenantName usha.com -Credential $cred -DlEligibilityListPath "C:\Users\umnaraya\Desktop\DLSCripts\DLEligibilityList.txt"


    DlMigrationModule.psm1 is needed for the execution of this script. It has to be placed in the first path of $env:PSModulePath
    
.OUTPUT

    MigrationOutput.txt --> Status of all the DLs attempted to migrate.
#>

param(
    [Parameter(HelpMessage = "Name of the tenant. For ex: microsoft.com")]
    [string] $TenantName = [string]::Empty,	

    [Parameter(Mandatory=$False, HelpMessage = "Admin credentials used to open new sessions")]
    [System.Management.Automation.PSCredential] $Credential,
      
    [Parameter(Mandatory=$False, HelpMessage = "Maximum number of PS sessions to use. Range: 1-3")]
    [ValidateRange(1,3)]
    [int] $NoOfConnections = 1,      
    
    [Parameter(Mandatory=$False, HelpMessage = "Exchange Online endpoint to connect to.")]
    [ValidateNotNullOrEmpty()]
    [string] $ConnectionUri = "https://outlook.office365.com/powershell-liveid/",

    [Parameter(Mandatory=$False, HelpMessage = "Path to store logs and output.")]
    [string] $WorkingDir = $(get-location).Path,

    [Parameter(Mandatory=$True, HelpMessage = "Path of the input list of DLs to migrate.")]
    [ValidateNotNullOrEmpty()]
    [string] $DlEligibilityListPath,

    [Parameter(Mandatory=$False, HelpMessage = "Is being executed by DCAdmin.")]
    [bool] $IsDCAdmin = $False,
    
    [Parameter(Mandatory=$False, HelpMessage = "Size of the batch for each session.")]
    [ValidateRange(1,500)]
    [int] $BatchSize = 50,    

    [Parameter(Mandatory=$False, HelpMessage = "Should closed DL be converted to a private group.")]
    [bool] $ConvertClosedDlToPrivateGroup = $True,

    [Parameter(Mandatory=$False, HelpMessage = "Should the DL be deleted after migration.")]
    [bool] $DeleteDlAfterMigration = $False
)

#------------------------------------------------------------------- Function Section Start --------------------------------------------------------------------------------------------


function Convert-EligibleDlDataToADictionary()
{
    param ($DLEligibilityListData, $ErrorLogsPath)

    $ExpectedHeader = @("ExternalDirectoryObjectId","PrimarySmtpAddress","Alias","Name","DisplayName","Eligibility","Reasons","MemberCount","MemberSmtpList", "OwnersDistinguishedName")    
    $ExpectedHeaderString = [string]::Join("`t",$ExpectedHeader)
    
    $header = $DLEligibilityListData[0]
    if($header -ne $ExpectedHeaderString)
    {
        Write-Host ([string]::Format("{0} {1}", $LocalizedStrings.Status, $LocalizedStrings.StatusHeaderNotMatching))
        Add-LogLine $ErrorLogsPath "STATUS: DlEligibilityList header is not matching. Actual : $header Expected : $ExpectedHeaderString"
        Exit
    }
    
    $dlList = New-Object 'System.Collections.Generic.List[System.Collections.Generic.Dictionary[System.String,System.String]]'

    for($rowCount = 1; $rowCount -lt $DLEligibilityListData.Count; $rowCount++)
    {
        $dict = New-Object 'System.Collections.Generic.Dictionary[System.String,System.String]'
        $fields = $DLEligibilityListData[$rowCount].Split("`t")

        if($fields.Count -ne $ExpectedHeader.Count)
        {
            Add-LogLine $ErrorLogsPath "Convert-EligibleDlDataToADictionary skipping row $fields. Number of columns are not matching."
            Write-Host ([string]::Format($LocalizedStrings.SkippingDl, $fields[0], $fields[1]))
        }
        else
        {
            for($columnCount=0; $columnCount -lt $ExpectedHeader.Count; $columnCount++)
            {
                $dict.Add($ExpectedHeader[$columnCount], $fields[$columnCount])
            }
            $dlList.Add($dict)
        }
    }    
    
    return ,$dlList
}

function PromptForConfirmation()
{
    param ($title, $message, $yesOptionHelp)

    $yes = New-Object System.Management.Automation.Host.ChoiceDescription $LocalizedStrings.ConfirmationYesOption, $yesOptionHelp;
    $no = New-Object System.Management.Automation.Host.ChoiceDescription $LocalizedStrings.ConfirmationNoOption, $LocalizedStrings.ExitFromScript;
    [System.Management.Automation.Host.ChoiceDescription[]]$options = $yes, $no;

    $confirmation = $host.ui.PromptForChoice($title, $message, $options, 0);
    if ($confirmation -ne 0)
    {
        Exit
    }
}

$MigrateDlsThreadJob = 
{
    param (
        [parameter(Mandatory=$true)]
        $DlsToMigrate,

        [parameter(Mandatory=$true)]
        [string] $Organization,

        [Parameter(Mandatory=$False)]
        [bool] $ConvertClosedDlToPrivateGroup = $False,

        [Parameter(Mandatory=$False)]
        [bool] $DeleteDlAfterMigration = $False,
        
        [parameter(Mandatory=$true)]
        [string] $OutputPath,

        [parameter(Mandatory=$true)]
        [string] $TraceLogsPath,

        [parameter(Mandatory=$true)]
        [string] $ErrorLogsPath,
        
        [parameter(Mandatory=$true)]
        [System.Management.Automation.PSCredential] $Credentials,

        [parameter(Mandatory=$true)]
        [string] $ConnectionUri,

        [Parameter(Mandatory=$False)]
        [bool] $IsDcAdmin = $False
    )

    $session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri $ConnectionUri -Credential $Credentials -Authentication Basic –AllowRedirection
    Import-PSSession $session -DisableNameChecking

    New-UnifiedGroupFromDistributionGroup $DlsToMigrate $Organization $ConvertClosedDlToPrivateGroup $DeleteDlAfterMigration $OutputPath $TraceLogsPath $ErrorLogsPath $IsDcAdmin
}

$ModuleInitializationScript = { 
    $DirSepChar = [IO.Path]::DirectorySeparatorChar
    $modulePath = $env:PSModulePath.Split(";")[0] + $DirSepChar + "DlMigrationModule.psm1"
    Import-Module $modulePath
} 

$DlMigrationHandlerForCancelEvent =
{
    Get-Job | Where-Object {$_.Name.StartsWith("DlMigration_") } | Stop-Job
    Get-Job | Where-Object {$_.Name.StartsWith("DlMigration_") } | Remove-Job
    $Global:ErrorActionPreference = "Continue"
}

#------------------------------------------------------------------- Function Section End --------------------------------------------------------------------------------------------


try
{
    $DirSepChar = [IO.Path]::DirectorySeparatorChar
    $modulePath = $env:PSModulePath.Split(";")[0] + $DirSepChar + "DlMigrationModule.psm1"
    Import-Module $modulePath
    $LocalizedStrings = $null
    Import-LocalizedData -BindingVariable LocalizedStrings -FileName DlMigration.strings.psd1 -BaseDirectory $env:PSModulePath.Split(";")[0]
    $error.Clear()

    <#--------------------------------------------------------------------------------------------------------------------------------------------------------
        INITIALIZATION: Create the log and output paths. Verify validity of dependent parameters.
    ---------------------------------------------------------------------------------------------------------------------------------------------------------#>        
    
    $TraceLogsPath = ([string]::Format("{0}{1}Logs{2}ConvertDlToUg_TraceLogs.txt", $WorkingDir, $DirSepChar, $DirSepChar))
    $ErrorLogsPath = ([string]::Format("{0}{1}Logs{2}ConvertDlToUg_ErrorLogs.txt", $WorkingDir, $DirSepChar, $DirSepChar))
    $MigrationOutputFilePath = ([string]::Format("{0}{1}MigrationOutput.txt", $WorkingDir, $DirSepChar))

    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -SupportEvent -Action $DlMigrationHandlerForCancelEvent
    Register-ObjectEvent -InputObject ([Console]) -EventName CancelKeyPress -Action $DlMigrationHandlerForCancelEvent -SupportEvent       
    
    if((Test-Path $TraceLogsPath) -eq $False)
    {
        $dirPath = $TraceLogsPath.Substring(0,$TraceLogsPath.LastIndexOf($DirSepChar))
        if((Test-Path $dirPath) -eq $False)
        {
            mkdir $dirPath | Out-Null
        }
        New-Item $TraceLogsPath -ItemType file | Out-Null
    }
    if((Test-Path $ErrorLogsPath) -eq $False)
    {
        $dirPath = $ErrorLogsPath.Substring(0,$ErrorLogsPath.LastIndexOf($DirSepChar))
        if((Test-Path $dirPath) -eq $False)
        {
            mkdir $dirPath | Out-Null
        }
        New-Item $ErrorLogsPath -ItemType file | Out-Null
    }

    Add-LogLine $TraceLogsPath ".................... Starting Migration Script"
    Add-LogLine $ErrorLogsPath ".................... Starting Migration Script"    
    
    # Since New-UnifiedGroup does not work for DC Admin today. Once this is fixed we can remove this check.
    if($IsDCAdmin)
    {
        Write-Error $LocalizedStrings.ParamValidateDcAdminNotSupported
        Add-LogLine $ErrorLogsPath "VALIDATION ERROR: Migration by DC Admin is not yet supported."
        Exit
    }

    if(($Credential -eq $null) -and ($NoOfConnections -ne 1))
    {
        Write-Error ([string]::Format($LocalizedStrings.ParamValidateSpecifyParam, "-Credential"))
        Add-LogLine $ErrorLogsPath "VALIDATION ERROR: Credentials are required if number of connections are more than 1."
        Exit
    }

    if($IsDCAdmin -and ([string]::IsNullOrEmpty($TenantName)))
    {
        Write-Error ([string]::Format($LocalizedStrings.ParamValidateSpecifyParam, "-TenantName"))
        Add-LogLine $ErrorLogsPath "VALIDATION ERROR: DC Admin must specify a tenant name."
        Exit
    }
    
    if(-not $IsDCAdmin)
    {
        $organization = Get-OrganizationConfig      
        if(($organization -eq $null) -or ($organization.Name -eq $null))
        {
           Write-Error ([string]::Format($LocalizedStrings.ParamValidateSpecifyParam, "-TenantName"))
           Add-LogLine $ErrorLogsPath "VALIDATION ERROR: More than one organization found. Please specify the TenantName."
           Exit 
        }
        else
        {
           $TenantName = $organization.Name
        }
    }

    if((Test-Path $MigrationOutputFilePath) -eq $True)
    {       
        Merge-FileContentFromIntermediate $MigrationOutputFilePath
        $MigrationOutputFilePathArchive = ([string]::Format("{0}_Archive_{1:yyyyMMddHHmmss}.txt", $MigrationOutputFilePath.Substring(0, $MigrationOutputFilePath.LastIndexOf(".")), [System.DateTime]::UtcNow))
        Copy-Item $MigrationOutputFilePath $MigrationOutputFilePathArchive
    }
    New-Item $MigrationOutputFilePath -ItemType file -force | Out-Null
    $migrationHeaders = @("DL-ExternalDirectoryObjectId","DL-PrimarySmtpAddress","UG-ExternalDirectoryObjectId","UG-PrimarySmtpAddress","MigrationStatus","ErrorMessage")        
    Add-Content $MigrationOutputFilePath ([string]::Join("`t", $migrationHeaders))
    
    Add-LogLine $TraceLogsPath ([string]::Format("Params: -TenanatName {0} -Credential {1} -NoOfConnections {2} -ConnectionUri {3} -BatchSize {4} -WorkingDir {5} -DLEligibilityList {6} -IsDCAdmin {7} ", `
                                                    $TenanatName, $Credential, $NoOfConnections, $ConnectionUri, $BatchSize, $WorkingDir, $DlEligibilityListPath, $IsDCAdmin))
    
   

    <#--------------------------------------------------------------------------------------------------------------------------------------------------------
        PHASE 1: Parse all the Mail Universal Distribution Groups that have been chosen for migration
        DlsToMigrate = DLEligibilityList ( from input file path)
    ---------------------------------------------------------------------------------------------------------------------------------------------------------#>    
    
    Add-LogLine $TraceLogsPath "Phase 1: Parse all the Mail Universal Distribution Groups that have been chosen for migration."
    Write-Host ([string]::Format("{0} {1} {2}", $LocalizedStrings.Status, $LocalizedStrings.Started, $LocalizedStrings.DlIdentifyingDlsToMigrate))
    $dlEligibilityData = Get-Content $DlEligibilityListPath
    if($dlEligibilityData.Count -le 1)
    {
        Write-Host ([string]::Format("{0} {1}", $LocalizedStrings.Status, $LocalizedStrings.StatusInputListHasNoData))
        Add-LogLine $ErrorLogsPath "STATUS: MailUniversalDLList has no data."
        Exit
    }

    $dlsToMigrate = Convert-EligibleDlDataToADictionary $dlEligibilityData $ErrorLogsPath    
      
    Add-LogLine $TraceLogsPath ([string]::Format("Phase 1: Finsihed parsing all the Mail Universal Distribution Groups that have been chosen for migration. Eligibility File length: {0}, Processed DL count: {1}, Dls To Migrate: {2}", $dlEligibilityData.Count - 1, 0, $dlsToMigrate.Count))
    Write-Host ([string]::Format($LocalizedStrings.DlIdentifyingDlsToMigrateFinish, $dlEligibilityData.Count - 1, $dlsToMigrate.Count, 0))
    
   <#--------------------------------------------------------------------------------------------------------------------------------------------------------
        PHASE 2: Migrate the DLs.
    ---------------------------------------------------------------------------------------------------------------------------------------------------------#>
    
    if($dlsToMigrate.Count -eq 0)
    {
        Write-Host $LocalizedStrings.NoDlsToMigrate
        Add-LogLine $TraceLogsPath "STATUS: There are no DLs to migrate."
        Exit
    }
    
    Add-LogLine $TraceLogsPath ([string]::Format( "PHASE 2: Migrate the DLs.") )
    $batchSize = $BatchSize * $NoOfConnections
    $start = 1
    if($dlsToMigrate.Count -gt $batchSize)
    {
        $end = $batchSize
    }
    else
    {
        $end = $dlsToMigrate.Count
    }

    $threadsSucceeded = $True
    while(($threadsSucceeded -eq $True) -and ($end -le $dlsToMigrate.Count))
    {            
        Write-Host ([string]::Format($LocalizedStrings.BatchStart, $LocalizedStrings.Status, $start, $end))
        Add-LogLine $TraceLogsPath ([string]::Format( "STATUS: Migrating DLs for batch starting $start ending $end.") )

        $jobNames = New-Object System.Collections.Generic.List[System.String]
        $outputPathOfThreads = New-Object System.Collections.Generic.List[System.String]
        for($threadNum = 0; $threadNum -lt $NoOfConnections; $threadNum++)
        { 
            $threadDlsToMigrate = New-Object 'System.Collections.Generic.List[System.Collections.Generic.Dictionary[System.String,System.String]]'
            for($i = $start; $i -le $end; $i++)
            {
                if(($i % $NoOfConnections) -eq $threadNum)
                {
                    $threadDlsToMigrate.Add($dlsToMigrate[$i-1])
                }
            }

            if($threadDlsToMigrate.Count -eq 0)
            {
                continue;
            }

            $outputPath = Get-OutputPathForThread $MigrationOutputFilePath $threadNum $true
            New-Item $outputPath -ItemType File -Force | Out-Null
            $outputPathOfThreads.Add($outputPath)
            $traceLogsPathThread = Get-OutputPathForThread $TraceLogsPath $threadNum
            $errorLogsPathThread = Get-OutputPathForThread $ErrorLogsPath $threadNum

            if($threadNum -eq ($NoOfConnections - 1))
            {
                $error.Clear();
                New-UnifiedGroupFromDistributionGroup $threadDlsToMigrate $TenantName $ConvertClosedDlToPrivateGroup $DeleteDlAfterMigration $outputPath $traceLogsPathThread $errorLogsPathThread $IsDCAdmin
            }
            else
            {
                $job = Start-Job -ScriptBlock $MigrateDlsThreadJob `
                                 -InitializationScript $ModuleInitializationScript `
                                 -ArgumentList($threadDlsToMigrate, $TenantName, $ConvertClosedDlToPrivateGroup, $DeleteDlAfterMigration, $outputPath, $traceLogsPathThread, $errorLogsPathThread, $Credential, $ConnectionUri, $IsDCAdmin)   `
                                 -Name "DlMigration_$threadNum"     
                $jobNames.Add($job.Name)
            }
        }

        if($jobNames.Count -gt 0)
        {
            $jobs = Get-Job -Name $jobNames
            $tmp = Wait-Job -Job $jobs 
            foreach($job in $jobs)
            {
                $error.Clear();
                $jobOutput = Receive-Job $job
                if($error.Count -gt 0)
                {
                    $threadsSucceeded = $False
                    Add-LogLine $ErrorLogsPath ([string]::Format("Convert-DistributionGroupToUnifiedGroup Thread failed with {0} errors. {1}", $error.Count, $error -join ";"))
                }
            }  
            $jobs | Remove-Job                 
        }
        
        $conversionCount = 0
        $conversionSuccessCount = 0 
        if($outputPathOfThreads.Count -gt 0)
        {
            foreach($path in $outputPathOfThreads)
            {
                $file = Get-Content $path
                Add-Content $MigrationOutputFilePath $file
                $conversionCount = $conversionCount + $file.Count
                $conversionSuccessCount = $conversionSuccessCount + ($file | Where-Object {$_.Contains("`tSuccess`t") } ).Count
                Remove-Item $path
            }
            Write-Host ([string]::Format($LocalizedStrings.BatchFinish, $LocalizedStrings.Status, $start, $end, $end - $start + 1, $conversionSuccessCount))
            Add-LogLine $TraceLogsPath ([string]::Format("STATUS: Finished Migrating DLs for batch starting {0} ending {1}. Processed Count: {2}, Succeeded Count: {3}", $start, $end, $end - $start + 1, $conversionSuccessCount))
        }

        $start = $end + 1
        if(($end + $batchSize) -gt $dlsToMigrate.Count)
        {
            $end = $dlsToMigrate.Count
        }
        else
        {
            $end = $end + $batchSize
        }        
        if($start -gt $end)
        {
            break
        }

        if($threadsSucceeded)
        {
            $confirmationText  = ([string]::Format($LocalizedStrings.ContinueWithNextBatchPrompt, $start, $end))
            PromptForConfirmation $LocalizedStrings.DlMigrationPopUpTitle $confirmationText $LocalizedStrings.ContinueNextBatch
        }
    }

    if($threadsSucceeded)
    {
        Write-Host ([string]::Format("{0} {1}", $LocalizedStrings.Status, $LocalizedStrings.ScriptSuccessful) )
        Add-LogLine $TraceLogsPath ([string]::Format( "STATUS: DLs were migrated successfully.") )
    }
    else
    {
        Write-Host ([string]::Format("{0} {1} {2}", $LocalizedStrings.Status, $LocalizedStrings.ScriptFailed, $ErrorLogsPath))
        Add-LogLine $ErrorLogsPath ([string]::Format( "STATUS: An error occured when migrating the DLs.") )
    }
    Add-LogLine $TraceLogsPath ([string]::Format( "Phase 2: Done migrating the DLs.") )
}
catch
{
    Write-Error ( $Error -join "`n")
}
finally
{    
    $Global:ErrorActionPreference = "Continue"
    foreach($err in $error)
    {
        Add-LogLine $ErrorLogsPath ([string]::Format( "Finally : {0}", $err))
    }
}
# SIG # Begin signature block
# MIId2QYJKoZIhvcNAQcCoIIdyjCCHcYCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUrhxsQ3id1ZBWxpmN7CWv9Hkz
# 04WgghhkMIIEwzCCA6ugAwIBAgITMwAAAJ1CaO4xHNdWvQAAAAAAnTANBgkqhkiG
# 9w0BAQUFADB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwHhcNMTYwMzMwMTkyMTMw
# WhcNMTcwNjMwMTkyMTMwWjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNO
# OjE0OEMtQzRCOS0yMDY2MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAy8PvNqh/8yl1
# MrZGvO1190vNqP7QS1rpo+Hg9+f2VOf/LWTsQoG0FDOwsQKDBCyrNu5TVc4+A4Zu
# vqN+7up2ZIr3FtVQsAf1K6TJSBp2JWunjswVBu47UAfP49PDIBLoDt1Y4aXzI+9N
# JbiaTwXjos6zYDKQ+v63NO6YEyfHfOpebr79gqbNghPv1hi9thBtvHMbXwkUZRmk
# ravqvD8DKiFGmBMOg/IuN8G/MPEhdImnlkYFBdnW4P0K9RFzvrABWmH3w2GEunax
# cOAmob9xbZZR8VftrfYCNkfHTFYGnaNNgRqV1rEFt866re8uexyNjOVfmR9+JBKU
# FbA0ELMPlQIDAQABo4IBCTCCAQUwHQYDVR0OBBYEFGTqT/M8KvKECWB0BhVGDK52
# +fM6MB8GA1UdIwQYMBaAFCM0+NlSRnAK7UD7dvuzK7DDNbMPMFQGA1UdHwRNMEsw
# SaBHoEWGQ2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3Rz
# L01pY3Jvc29mdFRpbWVTdGFtcFBDQS5jcmwwWAYIKwYBBQUHAQEETDBKMEgGCCsG
# AQUFBzAChjxodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY3Jv
# c29mdFRpbWVTdGFtcFBDQS5jcnQwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQEFBQADggEBAD9dHEh+Ry/aDJ1YARzBsTGeptnRBO73F/P7wF8dC7nTPNFU
# qtZhOyakS8NA/Zww74n4gvm1AWfHGjN1Ao8NiL3J6wFmmON/PEUdXA2zWFYhgeRe
# CPmATbwNN043ecHiGjWO+SeMYpvl1G4ma0NIUJau9DmTkfaMvNMK+/rNljr3MR8b
# xsSOZxx2iUiatN0ceMmIP5gS9vUpDxTZkxVsMfA5n63j18TOd4MJz+G0I62yqIvt
# Yy7GTx38SF56454wqMngiYcqM2Bjv6xu1GyHTUH7v/l21JBceIt03gmsIhlLNo8z
# Ii26X6D1sGCBEZV1YUyQC9IV2H625rVUyFZk8f4wggYHMIID76ADAgECAgphFmg0
# AAAAAAAcMA0GCSqGSIb3DQEBBQUAMF8xEzARBgoJkiaJk/IsZAEZFgNjb20xGTAX
# BgoJkiaJk/IsZAEZFgltaWNyb3NvZnQxLTArBgNVBAMTJE1pY3Jvc29mdCBSb290
# IENlcnRpZmljYXRlIEF1dGhvcml0eTAeFw0wNzA0MDMxMjUzMDlaFw0yMTA0MDMx
# MzAzMDlaMHcxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYD
# VQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xITAf
# BgNVBAMTGE1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQTCCASIwDQYJKoZIhvcNAQEB
# BQADggEPADCCAQoCggEBAJ+hbLHf20iSKnxrLhnhveLjxZlRI1Ctzt0YTiQP7tGn
# 0UytdDAgEesH1VSVFUmUG0KSrphcMCbaAGvoe73siQcP9w4EmPCJzB/LMySHnfL0
# Zxws/HvniB3q506jocEjU8qN+kXPCdBer9CwQgSi+aZsk2fXKNxGU7CG0OUoRi4n
# rIZPVVIM5AMs+2qQkDBuh/NZMJ36ftaXs+ghl3740hPzCLdTbVK0RZCfSABKR2YR
# JylmqJfk0waBSqL5hKcRRxQJgp+E7VV4/gGaHVAIhQAQMEbtt94jRrvELVSfrx54
# QTF3zJvfO4OToWECtR0Nsfz3m7IBziJLVP/5BcPCIAsCAwEAAaOCAaswggGnMA8G
# A1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFCM0+NlSRnAK7UD7dvuzK7DDNbMPMAsG
# A1UdDwQEAwIBhjAQBgkrBgEEAYI3FQEEAwIBADCBmAYDVR0jBIGQMIGNgBQOrIJg
# QFYnl+UlE/wq4QpTlVnkpKFjpGEwXzETMBEGCgmSJomT8ixkARkWA2NvbTEZMBcG
# CgmSJomT8ixkARkWCW1pY3Jvc29mdDEtMCsGA1UEAxMkTWljcm9zb2Z0IFJvb3Qg
# Q2VydGlmaWNhdGUgQXV0aG9yaXR5ghB5rRahSqClrUxzWPQHEy5lMFAGA1UdHwRJ
# MEcwRaBDoEGGP2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1
# Y3RzL21pY3Jvc29mdHJvb3RjZXJ0LmNybDBUBggrBgEFBQcBAQRIMEYwRAYIKwYB
# BQUHMAKGOGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljcm9z
# b2Z0Um9vdENlcnQuY3J0MBMGA1UdJQQMMAoGCCsGAQUFBwMIMA0GCSqGSIb3DQEB
# BQUAA4ICAQAQl4rDXANENt3ptK132855UU0BsS50cVttDBOrzr57j7gu1BKijG1i
# uFcCy04gE1CZ3XpA4le7r1iaHOEdAYasu3jyi9DsOwHu4r6PCgXIjUji8FMV3U+r
# kuTnjWrVgMHmlPIGL4UD6ZEqJCJw+/b85HiZLg33B+JwvBhOnY5rCnKVuKE5nGct
# xVEO6mJcPxaYiyA/4gcaMvnMMUp2MT0rcgvI6nA9/4UKE9/CCmGO8Ne4F+tOi3/F
# NSteo7/rvH0LQnvUU3Ih7jDKu3hlXFsBFwoUDtLaFJj1PLlmWLMtL+f5hYbMUVbo
# nXCUbKw5TNT2eb+qGHpiKe+imyk0BncaYsk9Hm0fgvALxyy7z0Oz5fnsfbXjpKh0
# NbhOxXEjEiZ2CzxSjHFaRkMUvLOzsE1nyJ9C/4B5IYCeFTBm6EISXhrIniIh0EPp
# K+m79EjMLNTYMoBMJipIJF9a6lbvpt6Znco6b72BJ3QGEe52Ib+bgsEnVLaxaj2J
# oXZhtG6hE6a/qkfwEm/9ijJssv7fUciMI8lmvZ0dhxJkAj0tr1mPuOQh5bWwymO0
# eFQF1EEuUKyUsKV4q7OglnUa2ZKHE3UiLzKoCG6gW4wlv6DvhMoh1useT8ma7kng
# 9wFlb4kLfchpyOZu6qeXzjEp/w7FW1zYTRuh2Povnj8uVRZryROj/TCCBhAwggP4
# oAMCAQICEzMAAABkR4SUhttBGTgAAAAAAGQwDQYJKoZIhvcNAQELBQAwfjELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEoMCYGA1UEAxMfTWljcm9z
# b2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAxMTAeFw0xNTEwMjgyMDMxNDZaFw0xNzAx
# MjgyMDMxNDZaMIGDMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MQ0wCwYDVQQLEwRNT1BSMR4wHAYDVQQDExVNaWNyb3NvZnQgQ29ycG9yYXRpb24w
# ggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCTLtrY5j6Y2RsPZF9NqFhN
# FDv3eoT8PBExOu+JwkotQaVIXd0Snu+rZig01X0qVXtMTYrywPGy01IVi7azCLiL
# UAvdf/tqCaDcZwTE8d+8dRggQL54LJlW3e71Lt0+QvlaHzCuARSKsIK1UaDibWX+
# 9xgKjTBtTTqnxfM2Le5fLKCSALEcTOLL9/8kJX/Xj8Ddl27Oshe2xxxEpyTKfoHm
# 5jG5FtldPtFo7r7NSNCGLK7cDiHBwIrD7huTWRP2xjuAchiIU/urvzA+oHe9Uoi/
# etjosJOtoRuM1H6mEFAQvuHIHGT6hy77xEdmFsCEezavX7qFRGwCDy3gsA4boj4l
# AgMBAAGjggF/MIIBezAfBgNVHSUEGDAWBggrBgEFBQcDAwYKKwYBBAGCN0wIATAd
# BgNVHQ4EFgQUWFZxBPC9uzP1g2jM54BG91ev0iIwUQYDVR0RBEowSKRGMEQxDTAL
# BgNVBAsTBE1PUFIxMzAxBgNVBAUTKjMxNjQyKzQ5ZThjM2YzLTIzNTktNDdmNi1h
# M2JlLTZjOGM0NzUxYzRiNjAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzcitW2oynUC
# lTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtp
# b3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEGCCsGAQUF
# BwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3Br
# aW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0MAwGA1Ud
# EwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAIjiDGRDHd1crow7hSS1nUDWvWas
# W1c12fToOsBFmRBN27SQ5Mt2UYEJ8LOTTfT1EuS9SCcUqm8t12uD1ManefzTJRtG
# ynYCiDKuUFT6A/mCAcWLs2MYSmPlsf4UOwzD0/KAuDwl6WCy8FW53DVKBS3rbmdj
# vDW+vCT5wN3nxO8DIlAUBbXMn7TJKAH2W7a/CDQ0p607Ivt3F7cqhEtrO1Rypehh
# bkKQj4y/ebwc56qWHJ8VNjE8HlhfJAk8pAliHzML1v3QlctPutozuZD3jKAO4WaV
# qJn5BJRHddW6l0SeCuZmBQHmNfXcz4+XZW/s88VTfGWjdSGPXC26k0LzV6mjEaEn
# S1G4t0RqMP90JnTEieJ6xFcIpILgcIvcEydLBVe0iiP9AXKYVjAPn6wBm69FKCQr
# IPWsMDsw9wQjaL8GHk4wCj0CmnixHQanTj2hKRc2G9GL9q7tAbo0kFNIFs0EYkbx
# Cn7lBOEqhBSTyaPS6CvjJZGwD0lNuapXDu72y4Hk4pgExQ3iEv/Ij5oVWwT8okie
# +fFLNcnVgeRrjkANgwoAyX58t0iqbefHqsg3RGSgMBu9MABcZ6FQKwih3Tj0DVPc
# gnJQle3c6xN3dZpuEgFcgJh/EyDXSdppZzJR4+Bbf5XA/Rcsq7g7X7xl4bJoNKLf
# cafOabJhpxfcFOowMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkqhkiG9w0B
# AQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAG
# A1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTEw
# HhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQgQ29kZSBT
# aWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA
# q/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03a8YS2Avw
# OMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akrrnoJr9eW
# WcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0RrrgOGSsbmQ1
# eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy4BI6t0le
# 2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9sbKvkjh+
# 0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAhdCVfGCi2
# zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8kA/DRelsv
# 1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTBw3J64HLn
# JN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmnEyimp31n
# gOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90lfdu+Hgg
# WCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0wggHpMBAG
# CSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2oynUClTAZ
# BgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/
# BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBaBgNVHR8E
# UzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9k
# dWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsGAQUFBwEB
# BFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9j
# ZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNVHSAEgZcw
# gZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsGAQUFBwIC
# MDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABlAG0AZQBu
# AHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKbC5YR4WOS
# mUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11lhJB9i0ZQ
# VdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6I/MTfaaQ
# dION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0wI/zRive
# /DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560STkKxgrC
# xq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQamASooPoI/
# E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGaJ+HNpZfQ
# 7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ahXJbYANah
# Rr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA9Z74v2u3
# S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33VtY5E90Z1W
# Tk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr/Xmfwb1t
# bWrJUnMTDXpQzTGCBN8wggTbAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcg
# UENBIDIwMTECEzMAAABkR4SUhttBGTgAAAAAAGQwCQYFKw4DAhoFAKCB8zAZBgkq
# hkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGC
# NwIBFTAjBgkqhkiG9w0BCQQxFgQUNMj9fm08jO1C0BQuzcMlpZu3/5kwgZIGCisG
# AQQBgjcCAQwxgYMwgYCgWIBWAEMAbwBuAHYAZQByAHQALQBEAGkAcwB0AHIAaQBi
# AHUAdABpAG8AbgBHAHIAbwB1AHAAVABvAFUAbgBpAGYAaQBlAGQARwByAG8AdQBw
# AC4AcABzADGhJIAiaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL2V4Y2hhbmdlIDAN
# BgkqhkiG9w0BAQEFAASCAQBB6FgI2DKVM+5gAP/h/E8Fa6lVe/+KjLgo0vWboaaN
# 6Z6ZaHzp5KoGZjlprigbxPNN/rkJUFva2Z9hF2PZ+BZ/mSuqeSuiGiPPWJRSsarL
# /dcIHI5Gi41EFY9Nn4yNhHDWv49w2j9xCS6yBwNc8CQ/meMWefFoxv8m8H1RHWos
# 6sZUbYn2S8PYHl1G9OsmOg423USKnwa+HEP2ekKFGMWA1x8pxuuwOAx68nqabxBg
# CHhJ88pvWq9Yv9msYxF/XptuY5VR+fkJvy1lY9e3Q5viGg+L3rlk1sdSGJTJ8xvS
# 6m/1XSyJcX52NUtiLpA4n9b045dnfn4FHSLyHCZLpAoGoYICKDCCAiQGCSqGSIb3
# DQEJBjGCAhUwggIRAgEBMIGOMHcxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xITAfBgNVBAMTGE1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQQITMwAA
# AJ1CaO4xHNdWvQAAAAAAnTAJBgUrDgMCGgUAoF0wGAYJKoZIhvcNAQkDMQsGCSqG
# SIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMTYwODEyMDM0NzI4WjAjBgkqhkiG9w0B
# CQQxFgQUpoN3fDd2bR4Abpg9ufsNOW9nBtIwDQYJKoZIhvcNAQEFBQAEggEAmhil
# fKbShNQmHRsnb5rf69Vyg/XjUJWhWb5rI+a7NJjXFoWbO4eX6zzv9C+d0Ecv9JqL
# FtgPYh3OrKPyex3ri8LyBgqYw1Zcd0ILP8tGl6R9pyzB8zZu4yuVqSLE+ci2W5Xq
# RD87r6pBU2YxrP84jFLmcm2ZluoOLBI24T9edPFyfnd2hYTkq6GAL374TFKg0c4C
# YQZUUkuPB/RVCxklnDVemgQHv4Zj/4G4HqLlGO/c/IqVqA/XrDDWz4KxGkDodPA/
# 49AepQhwpdYV9PfCvhH+3g5FnffAVyND5bTmo0W/NTme4ihjplPg/TJDAVRqgLdU
# vELOlufypvTSEBfLCA==
# SIG # End signature block
