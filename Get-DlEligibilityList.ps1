<# 
.SYNOPSIS
    The purpose of this script is to go through all the Distribution Groups [ RecipientTypeDetails = MailUniversalDistributionGroup ] in a given tenant 
    and give a detailed output indicating which of these DLs can or cannot be migrated to Unified Group.

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
    Some criteria can treated as warning and overriden in the migration script like:
        DL is a closed group. --> can be converted to private by specifying an override switch
        DL has custom delivery status notification --> ReportTo* properties will be copied to UG but the behaviour will be that DSN will always be sent to Originator

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

.PARAMETER ContinueFromPrevious
    true - If there is a DLEligibilityList in the working directory, considers only those DLs which are not processed.
    false - Starts fetching and checking DLs afresh.

.PARAMETER IsDcAdmin
    When the script is run by DC Ops, this has to be set as true. It puts in additional required params for certain cmdlets like Get-UnifiedGroup

.PARAMETER CustomFiltersOnAliasForDl
    In cases where the tenant has a large number of DLs, the Get-DistributionGroup will take a long time and fail. For such cases admin can decide what filter to use and process Dls in batches.
    The filter is on Alias.
    Ex: @( "a*", "b*" )

.PARAMETER BatchSize
    The script will process the DLs in batch size provided. After each batch, a status of number of DLs processed will be displayed and the results will be written to a file. 
    The script can be stopped and later resumed execution from this point by using $ContinueFromPrevious.

.EXAMPLE

    .\Get-DLEligibilityList.ps1 -TenantName Test113113yuq.ccsctp.net -Credential $cred -NoOfConnections 2 -ConnectionUri "https://sdfpilot.outlook.com/powershell-liveid/" -WorkingDir C:\MigrationLogs `
    -IsDcAdmin $false -ContinueFromPrevious $false

    DlMigrationModule.psm1 is needed for the execution of this script. It has to be placed in the first path of $env:PSModulePath

.OUTPUT

    MailUniversalDistributionGroupsList.txt --> List of all DLs in a tenant with the properties.
    DLEligibilityList.txt --> List if all DLs with Eligibility reasons and member list.
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

    [Parameter(Mandatory=$False, HelpMessage = "Continue from the state of previous run. Identified from Output file.")]
    [bool] $ContinueFromPrevious = $False,

    [Parameter(Mandatory=$False, HelpMessage = "Is being executed by DCAdmin.")]
    [bool] $IsDcAdmin = $False,

    [Parameter(Mandatory=$False, HelpMessage = "Filter to use on the Alias when fetching all the DLs in the tenant.")]
    [string[]] $CustomFiltersOnAliasForDl,
    
    [Parameter(Mandatory=$False, HelpMessage = "No of DLs to process at a time in a session.")]
    [ValidateRange(1,2400)]
    [int] $BatchSize = 300
)

#------------------------------------------------------------------- Function Section Start --------------------------------------------------------------------------------------------

<# 
 # Get all the MailUniversalDistributionGroups in the given tenant.
 # If the number of connections is n, then we have n tasks / PS Admin Sessions; fire background jobs for 0 to n-2 tasks and execute the n-1th task in the current thread.
#>
function Get-AllMailUniversalDistributionGroups()
{  
    $threadsSucceeded = $True

    $outputPathOfThreads = New-Object System.Collections.Generic.List[System.String]    
    $jobNames = New-Object System.Collections.Generic.List[System.String]
        
    for($threadNum=0; $threadNum -lt $NoOfConnections; $threadNum++)
    {   
        $subPattern = New-Object System.Collections.Generic.List[System.String]
        for($i = 0 ; $i -lt $CustomFiltersOnAliasForDl.Count ; $i++)
        {
            if(($i % $NoOfConnections) -eq $threadNum)
            {
                $subPattern.Add($CustomFiltersOnAliasForDl[$i])
            }
        }

        if($subPattern.Count -eq 0)
        {
            Add-LogLine $TraceLogsPath ([string]::Format("Get-AllMailUniversalDistributionGroups: Thread {0} has no data to process", $threadNum, $job.Name))
            continue;
        }

        $path = Get-OutputPathForThread $MailUniversalDlListPath $threadNum $true
        $newFile = New-Item $path -ItemType File -Force | Out-Null
        $outputPathOfThreads.Add($path)

        if($threadNum -eq ($NoOfConnections - 1))
        {
            $error.Clear();
            Get-FilteredMailUniversalDl $TenantName $path $subPattern
            if($error.Count -ne 0)
            {
                $threadsSucceeded = $False
                Add-LogLine $ErrorLogsPath ([string]::Format("Get-FilteredMailUniversalDl: Thread {0} failed with {1} errors. {2}", $threadNum, $error.Count, $error -join ";"))
            }
        }
        else
        {
            $job = Start-Job -ScriptBlock $GetFilteredDlFromBackgroundThreadJob `
                             -InitializationScript $ModuleInitializationScript `
                             -ArgumentList ($TenantName, $Credential, $ConnectionUri, $path, $subPattern) `
                             -Name "DlEligibility_AllDls_$threadNum"
            $jobNames.Add($job.Name)
        }
        Add-LogLine $TraceLogsPath ([string]::Format("Get-AllMailUniversalDistributionGroups: Started Thread {0} with name {1}. Pattern:{2}", $threadNum, $job.Name, ([string]::Join(",",$subPattern))))
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
                Add-LogLine $ErrorLogsPath ([string]::Format("GetFilteredDlFromBackgroundThreadJob failed with {0} errors. {1}", $error.Count, $error -join ";"))
            }
        }
        $jobs | Remove-Job
    }

    if($threadsSucceeded -and ($outputPathOfThreads.Count -gt 0))
    {
        $header = @("ExternalDirectoryObjectId","PrimarySmtpAddress","Alias","Name","DisplayName","MemberJoinRestriction","MemberDepartRestriction", `
                    "IsDirSynced","HiddenFromAddressListsEnabled","ReportToManagerEnabled","ReportToOriginatorEnabled","ModerationEnabled","GrantSendOnBehalfTo","MemberOfGroup")
        Add-Content $MailUniversalDlListPath ([string]::Join("`t",$header))
        foreach($path in $outputPathOfThreads)
        {
            $fileContent = Get-Content $path
            Add-Content $MailUniversalDlListPath $fileContent
        }
    }
    
    return $threadsSucceeded
}

$GetFilteredDlFromBackgroundThreadJob = 
{        
    param($tenantName, $credential, $connectionUri, $path, $patternList)

    $Session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri $connectionUri -Credential $credential -Authentication Basic –AllowRedirection
    Import-PSSession $Session -DisableNameChecking

    Get-FilteredMailUniversalDL $tenantName $path $patternList
}

function PromptForConfirmation()
{
    param ($title, $message)

    $yes = New-Object System.Management.Automation.Host.ChoiceDescription $LocalizedStrings.ConfirmationYesOption, $LocalizedStrings.FilesWillBeOverWritten;
    $no = New-Object System.Management.Automation.Host.ChoiceDescription $LocalizedStrings.ConfirmationNoOption, $LocalizedStrings.ExitFromScript;
    [System.Management.Automation.Host.ChoiceDescription[]]$options = $yes, $no;

    $confirmation = $host.ui.PromptForChoice($title, $message, $options, 0);
    if ($confirmation -ne 0)
    {
        Exit
    }
}

function Convert-DlDetailsToADictionary()
{
    param($dl)

    $ExpectedHeader = @("ExternalDirectoryObjectId","PrimarySmtpAddress","Alias","Name","DisplayName","MemberJoinRestriction","MemberDepartRestriction", `
                        "IsDirSynced","HiddenFromAddressListsEnabled","ReportToManagerEnabled","ReportToOriginatorEnabled","ModerationEnabled","GrantSendOnBehalfTo","MemberOfGroup")
    $dict = New-Object 'System.Collections.Generic.Dictionary[System.String,System.String]'
    
    $fields = $dl.Split("`t")
    if($fields.Count -ne $ExpectedHeader.Count)
    {
        Add-LogLine $ErrorLogsPath "Convert-DlDetailsToADictionary skipping row $fields. Number of columns are not matching."
    }
    else
    {
        for($i=0; $i -lt $ExpectedHeader.Count; $i++)
        {
            $dict.Add($ExpectedHeader[$i], $fields[$i])
        }
    }
    
    return $dict  
}

$GetDlEligibilityForGroupsThreadJob = 
{
    param (
        [parameter(Mandatory=$true)]
        [string] $TenantName,

        [parameter(Mandatory=$true)]
        $DlsToVerify,

        [parameter(Mandatory=$true)]
        [System.Management.Automation.PSCredential] $Credentials,

        [parameter(Mandatory=$true)]
        [string] $ConnectionUri,

        [parameter(Mandatory=$true)]
        [string] $OutputPath,

        [parameter(Mandatory=$true)]
        [string] $TraceLogsPath,

        [parameter(Mandatory=$true)]
        [string] $ErrorLogsPath,

        [parameter(Mandatory=$true)]
        [bool] $IsDcAdmin
    )

    $session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri $ConnectionUri -Credential $Credentials -Authentication Basic –AllowRedirection
    Import-PSSession $session -DisableNameChecking

    Publish-DlEligibilityForGroups $TenantName $DlsToVerify $OutputPath $TraceLogsPath $ErrorLogsPath $IsDcAdmin
}

$ModuleInitializationScript = 
{ 
    $DirSepChar = [IO.Path]::DirectorySeparatorChar
    $modulePath = $env:PSModulePath.Split(";")[0] + $DirSepChar + "DlMigrationModule.psm1"
    Import-Module $modulePath  
} 

<#
 # When script stop either because of Ctrl + C or Exit, we should stop all the child tasks also.
#>
$DlEligibilityHandlerForCancelEvent =
{
    Get-Job | Where-Object {$_.Name.StartsWith("DlEligibility_") } | Stop-Job
    Get-Job | Where-Object {$_.Name.StartsWith("DlEligibility_") } | Remove-Job
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
    $Error.Clear()
    <#--------------------------------------------------------------------------------------------------------------------------------------------------------
        INITIALIZATION: Create the log and output paths. Verify validity of dependent parameters.
    ---------------------------------------------------------------------------------------------------------------------------------------------------------#>        
    
    $TraceLogsPath = ([string]::Format("{0}{1}Logs{2}GetDlEligibilityList_TraceLogs.txt", $WorkingDir, $DirSepChar, $DirSepChar))
    $ErrorLogsPath = ([string]::Format("{0}{1}Logs{2}GetDlEligibilityList_ErrorLogs.txt", $WorkingDir, $DirSepChar, $DirSepChar))
    $DlEligibilityFilePath = ([string]::Format("{0}{1}DlEligibilityList.txt", $WorkingDir, $DirSepChar))
    $MailUniversalDlListPath = ([string]::Format("{0}{1}MailUniversalDistributionGroupsList.txt", $WorkingDir, $DirSepChar))     

    Register-EngineEvent -SourceIdentifier PowerShell.Exiting -SupportEvent -Action $DlEligibilityHandlerForCancelEvent
    Register-ObjectEvent -InputObject ([Console]) -EventName CancelKeyPress -Action $DlEligibilityHandlerForCancelEvent -SupportEvent       

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

    Add-LogLine $TraceLogsPath ".................... Starting Eligibility Script"
    Add-LogLine $ErrorLogsPath ".................... Starting Eligibility Script"    
      
    
    if($ContinueFromPrevious -and ($CustomFiltersOnAliasForDl -ne $null))
    {
        Write-Error ([string]::Format($LocalizedStrings.ParamValidateUseTogether, "-ContinueFromPrevious -CustomFiltersOnAliasForDl"))
        Add-LogLine $ErrorLogsPath "VALIDATION ERROR: You cannot specify CustomFiltersOnAliasForDl when ContinueFromPrevious is set."
        Exit
    }
    
    if($IsDcAdmin -and ($NoOfConnections -ne 1))
    {
        Write-Error $LocalizedStrings.ParamValidateDcAdminMultipleConnections
        Add-LogLine $ErrorLogsPath "VALIDATION ERROR: DC Admin cannot use multiple connections."
        Exit
    }

    if(($Credential -eq $null) -and ($NoOfConnections -ne 1))
    {
        Write-Error ([string]::Format($LocalizedStrings.ParamValidateSpecifyParam, "-Credential"))
        Add-LogLine $ErrorLogsPath "VALIDATION ERROR: Credentials are required if number of connections are more than 1."
        Exit
    }

    if($IsDcAdmin -and ([string]::IsNullOrEmpty($TenantName)))
    {
        Write-Error  ([string]::Format($LocalizedStrings.ParamValidateSpecifyParam, "-TenantName"))
        Add-LogLine $ErrorLogsPath "VALIDATION ERROR: DC Admin must specify a tenant name."
        Exit
    }
    
    if(-not $IsDcAdmin)
    {
        $organization = Get-OrganizationConfig        
        if(($organization -eq $null) -or ($organization.Name -eq $null))
        {
           Write-Error ([string]::Format($LocalizedStrings.ParamValidateSpecifyParam, "-TenantName"))
           Add-LogLine $ErrorLogsPath "VALIDATION ERROR: Default OrganizationConfig not found. Please specify the TenantName."
           Exit 
        }
        else
        {
           $TenantName = $organization.Name
        }
    }    
    
    $dataExistsFromPrev = (Test-Path $DlEligibilityFilePath) -or (Test-Path $MailUniversalDlListPath)
    if($dataExistsFromPrev -and ($ContinueFromPrevious -eq $false))
    {        
        PromptForConfirmation $LocalizedStrings.DlEligibilityPopUpTitle $LocalizedStrings.DlEligibilityOutputOverwrite
    }
   
    $DlListNew = $False
    if(((Test-Path $MailUniversalDlListPath) -eq $False) -or ($ContinueFromPrevious -eq $false))
    {
        New-Item $MailUniversalDlListPath -ItemType file -force | Out-Null
        $DlListNew = $True
    }
    if(((Test-Path $DlEligibilityFilePath) -eq $False) -or ($ContinueFromPrevious -eq $false))
    {
        New-Item $DlEligibilityFilePath -ItemType file -force | Out-Null
        $headers = @("ExternalDirectoryObjectId","PrimarySmtpAddress","Alias","Name","DisplayName","Eligibility","Reasons","MemberCount","MemberSmtpList","OwnersDistinguishedName")        
        Add-Content $DlEligibilityFilePath ([string]::Join("`t", $headers))
    }
    else
    {
        Merge-FileContentFromIntermediate $DlEligibilityFilePath
    }

    if($CustomFiltersOnAliasForDl -eq $null)
    {
        $CustomFiltersOnAliasForDl = @("*")
    }
    
    Add-LogLine $TraceLogsPath ([string]::Format("Params: -TenanatName {0} -Credential {1} -ContinueFromPrevious {2} -NoOfConnections {3} -ConnectionUri {4} -WorkingDir {5} -IsDcAdmin {6} -CustomFiltersOnAliasForDl {7}", `
                                                    $TenanatName, $Credential, $ContinueFromPrevious, $NoOfConnections, $ConnectionUri, $WorkingDir, $IsDcAdmin, ([string]::Join(",",$CustomFiltersOnAliasForDl))))
    
    <#--------------------------------------------------------------------------------------------------------------------------------------------------------
        PHASE 1: Get all the Mail Universal Distribution Groups in the given tenant and store in a file.
        If DL List is available skip this step
    ---------------------------------------------------------------------------------------------------------------------------------------------------------#>    
    if($DlListNew)
    {
        Add-LogLine $TraceLogsPath "Phase 1: Started getting all Mail Universal DGs in the tenant."
        Write-Host ([string]::Format("{0} {1} {2}",$LocalizedStrings.Status, $LocalizedStrings.Started, $LocalizedStrings.GetAllDls))
        $ret = Get-AllMailUniversalDistributionGroups
        if($ret -eq $False)
        {
            Write-Host ([string]::Format("{0} {1} {2}",$LocalizedStrings.Status, $LocalizedStrings.ErrorFetchingDls , $ErrorLogsPath))
            Add-LogLine $ErrorLogsPath "Phase 1: Failed fetching all the DGs in the tenant."
            Exit
        }
        Add-LogLine $TraceLogsPath "Phase 1: Finished getting all Mail Universal DGs in the tenant."
        Write-Host ([string]::Format("{0} {1} {2}",$LocalizedStrings.Status, $LocalizedStrings.Finished, $LocalizedStrings.GetAllDls))
    }    

    <#--------------------------------------------------------------------------------------------------------------------------------------------------------
        PHASE 2: Identify the list of DLs to check for Eligibility in this run.
        DlsToVerify = DLs in $MailUniversalDlListPath (all dls) - DLs in $DlEligibilityFilePath (processed dls)
    ---------------------------------------------------------------------------------------------------------------------------------------------------------#>  
    Add-LogLine $TraceLogsPath "Phase 2: Identify the list of DLs to check for Eligibility in this run."
    Write-Host ([string]::Format("{0} {1} {2}", $LocalizedStrings.Status, $LocalizedStrings.Started, $LocalizedStrings.StatusStartedIdentifyingDls))
    $DlsToVerify = New-Object 'System.Collections.Generic.List[System.Collections.Generic.Dictionary[System.String,System.String]]'
    
    # Get the Content of MailUniversalDlList (all dls)
    $dlList = Get-Content $MailUniversalDlListPath
    if($dlList.Count -le 1)
    {
        Write-Host ([string]::Format("{0} {1}", $LocalizedStrings.Status, $LocalizedStrings.StatusInputListHasNoData))
        Add-LogLine $ErrorLogsPath "STATUS: MailUniversalDlList has no data."
        Exit
    }
    $dlListHeader = $dlList[0]
    $ExpectedHeaderDlList = @("ExternalDirectoryObjectId","PrimarySmtpAddress","Alias","Name","DisplayName", "MemberJoinRestriction","MemberDepartRestriction", `
                        "IsDirSynced","HiddenFromAddressListsEnabled","ReportToManagerEnabled","ReportToOriginatorEnabled","ModerationEnabled","GrantSendOnBehalfTo","MemberOfGroup")
    $ExpectedHeaderStringDlList = [string]::Join("`t",$ExpectedHeaderDlList)
    if($dlListHeader -ne $ExpectedHeaderStringDlList)
    {
        Write-Host ([string]::Format("{0} {1} {2} {3}", $LocalizedStrings.Status, $LocalizedStrings.StatusHeaderNotMatching, $LocalizedStrings.RerunScriptWithout, "-ContinueFromPrevious"))
        Add-LogLine $ErrorLogsPath "STATUS: MailUniversalDlList header is not matching.. Actual : $dlListHeader Expected : $ExpectedHeaderStringDlList"
        Exit
    }

    # Get the content of DlEligibilityList (processed dls), Column 0 has the ExternalDirectoryObjectId
    $processedDls = Get-Content $DlEligibilityFilePath | ForEach-Object { $_.Split("`t")[0] }

    # Calculate Dls to verify
    for($i = 1; $i -lt $dlList.Length; $i++)
    {
        $dl = $dlList[$i]
        $extId = $dl.Split("`t")[0] 
        if(($processedDls -eq $null) -or (-not $processedDls.Contains($extId)))
        {            
            $dlDataDict = Convert-DlDetailsToADictionary $dl
            if(($dlDataDict -ne $null) -and $dlDataDict.Count -gt 0)
            {
                $DlsToVerify.Add($dlDataDict)
            }
        }
    }

    Add-LogLine $TraceLogsPath ([string]::Format("Phase 2: Done identifying the list of DLs to check for Eligibility in this run. File length: {0}, Dls to verify: {1}, Processed DL count: {2}", $dlList.Length-1, $DlsToVerify.Count, $processedDls.Count - 1))
    Write-Host ([string]::Format($LocalizedStrings.StatusFinishedIdentifyingDls, $dlList.Length-1, $DlsToVerify.Count, $processedDls.Count - 1))

   <#--------------------------------------------------------------------------------------------------------------------------------------------------------
        PHASE 3: Check if the DLs are eligible for migration.
        DlsToVerify = DLs in $MailUniversalDlListPath (all dls) - DLs in $DlEligibilityFilePath (processed dls)
    ---------------------------------------------------------------------------------------------------------------------------------------------------------#>
    
    if($DlsToVerify.Count -eq 0)
    {
        Write-Host ([string]::Format("{0} {1}", $LocalizedStrings.Status, $LocalizedStrings.StatusInputListHasNoData))
        Add-LogLine $TraceLogsPath "STATUS: There are no DLs to checks for eligibility."
        Exit
    }
    
    Add-LogLine $TraceLogsPath ([string]::Format( "Phase 3: Check if the DLs are eligible for migration.") )
    $batchSize = $BatchSize * $NoOfConnections
    $start = 1
    if($DlsToVerify.Count -gt $batchSize)
    {
        $end = $batchSize
    }
    else
    {
        $end = $DlsToVerify.Count
    }
   
    $threadsSucceeded = $True
    while($threadsSucceeded -and ($end -le $DlsToVerify.Count))
    {            
        Write-Host ([string]::Format($LocalizedStrings.BatchStart, $LocalizedStrings.Status, $start, $end))
        Add-LogLine $TraceLogsPath ([string]::Format( "STATUS: Checking Eligibility for batch starting $start ending $end.") )

        $jobNames = New-Object System.Collections.Generic.List[System.String]
        $outputPathOfThreads = New-Object System.Collections.Generic.List[System.String]
        for($threadNum = 0; $threadNum -lt $NoOfConnections; $threadNum++)
        { 
            $threadDlsToVerify = New-Object 'System.Collections.Generic.List[System.Collections.Generic.Dictionary[System.String,System.String]]'
            for($i = $start; $i -le $end; $i++)
            {
                if(($i % $NoOfConnections) -eq $threadNum)
                {
                    
                    $threadDlsToVerify.Add($DlsToVerify[$i-1])
                }
            }

            if($threadDlsToVerify.Count -eq 0)
            {
                continue;
            }

            $outputPath = Get-OutputPathForThread $DlEligibilityFilePath $threadNum $true
            New-Item $outputPath -ItemType File -Force | Out-Null
            $outputPathOfThreads.Add($outputPath)
            $traceLogsPathThread = Get-OutputPathForThread $TraceLogsPath $threadNum
            $errorLogsPathThread = Get-OutputPathForThread $ErrorLogsPath $threadNum

            if($threadNum -eq ($NoOfConnections - 1))
            {
                $error.Clear();
                Publish-DlEligibilityForGroups $TenantName $threadDlsToVerify $outputPath $traceLogsPathThread $errorLogsPathThread $IsDcAdmin
                if($error.Count -ne 0)
                {
                    $threadsSucceeded = $False
                    Add-LogLine $ErrorLogsPath ([string]::Format("Publish-DlEligibilityForGroups failed with {0} errors. {1}", $error.Count, $error -join ";"))
                }
            }
            else
            {
                $job = Start-Job -ScriptBlock $GetDlEligibilityForGroupsThreadJob `
                                 -InitializationScript $ModuleInitializationScript `
                                 -ArgumentList($TenantName, $threadDlsToVerify, $Credential, $ConnectionUri, $outputPath, $traceLogsPathThread, $errorLogsPathThread, $IsDcAdmin)  `
                                 -Name "DlEligibility_CheckDls_$threadNum"
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
                    Add-LogLine $ErrorLogsPath ([string]::Format("Publish-DlEligibilityForGroups Thread failed with {0} errors. {1}", $error.Count, $error -join ";"))
                }
            }
            $jobs | Remove-Job
        }

        $eligibilityCount = 0
        $eligibilitySuccessCount = 0
        $unknownErrorString =$LocalizedStrings.UnknownError
        if($threadsSucceeded -and ($outputPathOfThreads.Count -gt 0))
        {
            foreach($path in $outputPathOfThreads)
            {
                $file = Get-Content $path
                Add-Content $DlEligibilityFilePath $file
                $eligibilityCount = $eligibilityCount + $file.Count  
                $eligibilitySuccessCount = $eligibilitySuccessCount + ($file.Count - ($file | Where-Object {$_.Contains("`t$unknownErrorString`t") } ).Count)
                Remove-Item $path
            }
            Write-Host ([string]::Format($LocalizedStrings.BatchFinish, $LocalizedStrings.Status, $start, $end, $eligibilityCount, $eligibilitySuccessCount))
            Add-LogLine $TraceLogsPath ([string]::Format("STATUS: Finished processing batch starting {0} ending {1}. Processed Count: {2}, Succeeded Count: {3}.", $start, $end, $eligibilityCount, $eligibilitySuccessCount))
        }

        $start = $end + 1
        if(($end + $batchSize) -gt $DlsToVerify.Count)
        {
            $end = $DlsToVerify.Count
        }
        else
        {
            $end = $end + $batchSize
        }        
        if($start -gt $end)
        {
            break
        }
    }
    if($threadsSucceeded)
    {
        Write-Host ([string]::Format("{0} {1}", $LocalizedStrings.Status, $LocalizedStrings.ScriptSuccessful) )
        Add-LogLine $TraceLogsPath ([string]::Format( "STATUS: Finished checking if the DLs are eligible for migration."))
    }
    else
    {
        Write-Host ([string]::Format("{0} {1} {2}", $LocalizedStrings.Status, $LocalizedStrings.ScriptFailed, $ErrorLogsPath))
        Add-LogLine $ErrorLogsPath ([string]::Format( "STATUS: Error occured in checking the DLs for eligibility.") )
    }
    Add-LogLine $TraceLogsPath ([string]::Format( "Phase 3: Done Checking if the DLs are eligible for migration.") )
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
        Add-LogLine $ErrorLogsPath ([string]::Format( "Finally: {0}", $err))
    }
}
# SIG # Begin signature block
# MIIdsgYJKoZIhvcNAQcCoIIdozCCHZ8CAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUfhiUte4G4SdscuwOruwW7bCu
# De2gghhkMIIEwzCCA6ugAwIBAgITMwAAAJqamxbCg9rVwgAAAAAAmjANBgkqhkiG
# 9w0BAQUFADB3MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSEw
# HwYDVQQDExhNaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EwHhcNMTYwMzMwMTkyMTI5
# WhcNMTcwNjMwMTkyMTI5WjCBszELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjENMAsGA1UECxMETU9QUjEnMCUGA1UECxMebkNpcGhlciBEU0UgRVNO
# OkIxQjctRjY3Ri1GRUMyMSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBT
# ZXJ2aWNlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEApkZzIcoArX4o
# w+UTmzOJxzgIkiUmrRH8nxQVgnNiYyXy7kx7X5moPKzmIIBX5ocSdQ/eegetpDxH
# sNeFhKBOl13fmCi+AFExanGCE0d7+8l79hdJSSTOF7ZNeUeETWOP47QlDKScLir2
# qLZ1xxx48MYAqbSO30y5xwb9cCr4jtAhHoOBZQycQKKUriomKVqMSp5bYUycVJ6w
# POqSJ3BeTuMnYuLgNkqc9eH9Wzfez10Bywp1zPze29i0g1TLe4MphlEQI0fBK3HM
# r5bOXHzKmsVcAMGPasrUkqfYr+u+FZu0qB3Ea4R8WHSwNmSP0oIs+Ay5LApWeh/o
# CYepBt8c1QIDAQABo4IBCTCCAQUwHQYDVR0OBBYEFCaaBu+RdPA6CKfbWxTt3QcK
# IC8JMB8GA1UdIwQYMBaAFCM0+NlSRnAK7UD7dvuzK7DDNbMPMFQGA1UdHwRNMEsw
# SaBHoEWGQ2h0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3Rz
# L01pY3Jvc29mdFRpbWVTdGFtcFBDQS5jcmwwWAYIKwYBBQUHAQEETDBKMEgGCCsG
# AQUFBzAChjxodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY3Jv
# c29mdFRpbWVTdGFtcFBDQS5jcnQwEwYDVR0lBAwwCgYIKwYBBQUHAwgwDQYJKoZI
# hvcNAQEFBQADggEBAIl6HAYUhsO/7lN8D/8YoxYAbFTD0plm82rFs1Mff9WBX1Hz
# /PouqK/RjREf2rdEo3ACEE2whPaeNVeTg94mrJvjzziyQ4gry+VXS9ZSa1xtMBEC
# 76lRlsHigr9nq5oQIIQUqfL86uiYglJ1fAPe3FEkrW6ZeyG6oSos9WPEATTX5aAM
# SdQK3W4BC7EvaXFT8Y8Rw+XbDQt9LJSGTWcXedgoeuWg7lS8N3LxmovUdzhgU6+D
# ZJwyXr5XLp2l5nvx6Xo0d5EedEyqx0vn3GrheVrJWiDRM5vl9+OjuXrudZhSj9WI
# 4qu3Kqx+ioEpG9FwqQ8Ps2alWrWOvVy891W8+RAwggYHMIID76ADAgECAgphFmg0
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
# bWrJUnMTDXpQzTGCBLgwggS0AgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcg
# UENBIDIwMTECEzMAAABkR4SUhttBGTgAAAAAAGQwCQYFKw4DAhoFAKCBzDAZBgkq
# hkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGC
# NwIBFTAjBgkqhkiG9w0BCQQxFgQUzBuD5awXEK+nwQylv+2Q/8N2xcAwbAYKKwYB
# BAGCNwIBDDFeMFygNIAyAEcAZQB0AC0ARABsAEUAbABpAGcAaQBiAGkAbABpAHQA
# eQBMAGkAcwB0AC4AcABzADGhJIAiaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL2V4
# Y2hhbmdlIDANBgkqhkiG9w0BAQEFAASCAQCJ7tyuy1QuPbZxBBIiNsJP01gAXm9E
# b2jskHKA1jP9bKY32RJYfoJm2/maRkxV2DHhkv6/i1l5uGnvl7PurKOlqBkvLQoN
# GV9OnCu7FmNt+MxgNg307gvrGKSPMc33l4iKlijqns4N6UEwSjiw+TlooVtJdRan
# BAUj/6VTUrhio+N/ezO7SPhYbNNSn0827d7zw/zZAgbLaPKqa44g9t6zUbPfbzAK
# DA+TTCl+SWJCEW5TPV36Ed2LBQccNF5mJVgO0o1C9sDdX/7ddrOtgCg/6cgQfvIq
# KE6gi/eTizK0nQ4YQyUbm+6lIHTcBv0qkuKnFcD2btoeulZcBm0oT+F/oYICKDCC
# AiQGCSqGSIb3DQEJBjGCAhUwggIRAgEBMIGOMHcxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xITAfBgNVBAMTGE1pY3Jvc29mdCBUaW1lLVN0YW1w
# IFBDQQITMwAAAJqamxbCg9rVwgAAAAAAmjAJBgUrDgMCGgUAoF0wGAYJKoZIhvcN
# AQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMTYwODEyMDM0NzQ4WjAj
# BgkqhkiG9w0BCQQxFgQU4D+om92Lc2y2ji/c+9+yZBsfPKswDQYJKoZIhvcNAQEF
# BQAEggEAEieZW1mJ5aAqnsrOLFbNgT2yPmqSDlpNP9RSdo3Ys1yTROlXxca8BTc/
# phfybO3vUMHf/6ajMigAormiNRl1/pmuV4vHV0SP9yL005nK97hL+vWPIJO4SOFk
# LNYlOp73+lqAbVhhE3P0Fut5MAoXicxNw1dyy+a/uqvUdbyPgirXLep0ccdJ0jWm
# jUw0TeQhfOWv2FZJ8NFJTx/8IWlefQvoIZgrza+UT12QVy1Bh8ZrNJoP4RoocKek
# DAMwN3JLh9EhgdIAL+hJpYbKzePO9Zj6w/mDOGvAhiE4aHOCgjqwHGAcDZELHIrA
# hiVpEMivZ9oZ1B8RVEsLecIZZoiIwg==
# SIG # End signature block
