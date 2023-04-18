<#
.SYNOPSIS
    This module provides functions to check all the DL eligibility criteria. Its also exposes other common functions and types which can be used by all the DL Migration scripts.
#>

<# --------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Type definitions
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------#>

if (-not ("UnifiedGroupType" -as [type]))
{
Add-Type -TypeDefinition @" 
    public enum UnifiedGroupType
    {
        Unknown,
        Public,
        Private,
        Closed
    }
"@
}


if(-not ("DlEligibilityType" -as [type]))
{
Add-Type -TypeDefinition @"
    public enum DlEligibilityType
    {
        Eligible,
        Information,
        Warning,
        NotEligible
    }
"@
}

if(-not ("DlMigrationStatus" -as [type]))
{
Add-Type -TypeDefinition @"
    public enum DlMigrationStatus
    {
        Success,
        SuccessActionRequired,
        Failure,
        FailureActionRequired,
        NotEligible,
        UnknownError,
        Running
    }
"@
}


<# --------------------------------------------------------------------------------------------------------------------------------------------------------------------------
DL Eligibility helper functions
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------#>

function Get-DlGroupType()
{
    param ($dl)

    $groupType = [UnifiedGroupType]::Unknown

    if(($dl.MemberDepartRestriction -eq "Closed") -or ($dl.MemberJoinRestriction -eq "Closed"))
    {
        $groupType = [UnifiedGroupType]::Closed
    }
    elseif(($dl.MemberDepartRestriction -eq "Open") -and ($dl.MemberJoinRestriction -eq "Open"))
    {
        $groupType = [UnifiedGroupType]::Public
    }
    elseif(($dl.MemberDepartRestriction -eq "Open") -and ($dl.MemberJoinRestriction -eq "ApprovalRequired"))
    {
        $groupType = [UnifiedGroupType]::Private
    }

    return $groupType
}

function Get-DlHasDeliveryStatusSet()
{
    param ($dl)

    if( ($dl.ReportToManagerEnabled -eq $false) -and ($dl.ReportToOriginatorEnabled -eq $true))
    {
        return $false
    }
    else
    {
        return $true
    }
}

function Get-DlHasChildGroups()
{
    param ($members)

    $possibleChildGroupTypes = New-Object System.Collections.Generic.List[System.String]
    $possibleChildGroupTypes.Add("MailUniversalDistributionGroup")
    $possibleChildGroupTypes.Add("MailNonUniversalGroup")
    $possibleChildGroupTypes.Add("MailUniversalSecurityGroup")
    $possibleChildGroupTypes.Add("DynamicDistributionGroup")
    $possibleChildGroupTypes.Add("UniversalDistributionGroup")
    $possibleChildGroupTypes.Add("UniversalSecurityGroup")
    $possibleChildGroupTypes.Add("NonUniversalGroup")
    $possibleChildGroupTypes.Add("GroupMailbox")
    $possibleChildGroupTypes.Add("RemoteGroupMailbox")
    
    foreach($mem in $members)
    {
        if(($possibleChildGroupTypes -contains $mem.RecipientTypeDetails) -or ($mem.ObjectClass[$mem.ObjectClass.Count - 1] -eq "group"))
        {
            return $true
        }
    }   
    return $false 
}

function Get-DlHasNonSupportedMemberTypes()
{
    param ($members, $owners)

    $allowedMemberTypes = New-Object System.Collections.Generic.List[System.String]
    $allowedMemberTypes.Add("UserMailbox")
    $allowedMemberTypes.Add("SharedMailbox")
    $allowedMemberTypes.Add("TeamMailbox")
    $allowedMemberTypes.Add("MailUser")

    foreach($mem in $members)
    {
        if($allowedMemberTypes -notcontains $mem.RecipientTypeDetails)
        {
            return $true
        }
    }  
    foreach($mem in $owners)
    {
        if($allowedMemberTypes -notcontains $mem.RecipientTypeDetails)
        {
            return $true
        }
    }   
    return $false     
}

function Get-DlEligibilityBasedOnReasons()
{
    param ([System.Collections.Generic.List[System.String]]$ReasonsList)
    
    $InvalidReasons = New-Object System.Collections.Generic.List[System.String]
    $InvalidReasons.Add($LocalizedStrings.UnknownError)
    $InvalidReasons.Add($LocalizedStrings.IsDirSyncedDl)
    $InvalidReasons.Add($LocalizedStrings.HalNotSupported)  
    $InvalidReasons.Add($LocalizedStrings.ModerationNotSupported)
    $InvalidReasons.Add($LocalizedStrings.SendOnBehalfNotSupported)
    $InvalidReasons.Add($LocalizedStrings.HasChildDls)
    $InvalidReasons.Add($LocalizedStrings.IsNested)    
    $InvalidReasons.Add($LocalizedStrings.NonSupportedMemberTypes)

    $WarningReasons = New-Object System.Collections.Generic.List[System.String]

    $InfoReasons = New-Object System.Collections.Generic.List[System.String]
    $InfoReasons.Add($LocalizedStrings.DeliveryStatusNotSupported)
    $InfoReasons.Add($LocalizedStrings.DlAlreadyMigrated)    
    $InfoReasons.Add($LocalizedStrings.ClosedGroupNotSupported)  

    $hasInvalid = $false
    $hasWarning = $false
    $hasInfo = $false

    foreach($reason in $ReasonsList)
    {
        if($InvalidReasons.Contains($reason))
        {
            $hasInvalid = $true
        }
        elseif($WarningReasons.Contains($reason))
        {
            $hasWarning = $true
        }
        elseif($InfoReasons.Contains($reason))
        {
            $hasInfo = $true
        }
    }

    if($hasInvalid)
    {
        return [DlEligibilityType]::NotEligible
    }
    elseif($hasWarning)
    {
        return [DlEligibilityType]::Warning
    }  
    elseif($hasInfo)
    {
        return [DlEligibilityType]::Information
    }   
    else
    {
        return [DlEligibilityType]::Eligible
    }
}

<# --------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Migration helper functions
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------#>

function Add-LogLine()
{
    param($LogPath, $Message)
    $now = [System.DateTime]::UtcNow
    Add-Content $LogPath ( [string]::Format("[{0:yyyy-MM-dd HH:mm:ss}] {1}", $now, $Message) )
}

function Get-OutputPathForThread()
{
    param($originalFilePath, $threadNum, $putInIntermediate=$false)

    $dirSep = [IO.Path]::DirectorySeparatorChar
    $indexOfExt = $originalFilePath.LastIndexOf(".")
    $indexOfDirSep = $originalFilePath.LastIndexOf($dirSep)
    $basePath = $originalFilePath.Substring(0,$indexOfDirSep)
    $filename = $originalFilePath.Substring($indexOfDirSep, $indexOfExt - $indexOfDirSep)
    $extension = $originalFilePath.Substring($indexOfExt)
    if($putInIntermediate)
    {
        $threadFilePath = [string]::Format("{0}{1}Intermediate{2}_{3}{4}", $basePath, $dirSep, $filename, $threadNum, $extension)
    }
    else
    {
        $threadFilePath = [string]::Format("{0}{1}_{2}{3}", $basePath, $filename, $threadNum, $extension)
    }
    return $threadFilePath
}

function Publish-DlEligibilityForGroups()
{
    param (
        [parameter(Mandatory=$true)]
        [string] $TenantName,

        [parameter(Mandatory=$true)]
        $DlsToVerify,
        
        [parameter(Mandatory=$true)]
        [string] $OutputPath,

        [parameter(Mandatory=$true)]
        [string] $TraceLogsPath,

        [parameter(Mandatory=$true)]
        [string] $ErrorLogsPath,

        [parameter(Mandatory=$false)]
        [bool] $IsDCAdmin = $false
    )

    $OperationName = "Publish-DlEligibilityForGroups"
    $backUpErrorActionPreference = $Global:ErrorActionPreference
    $Global:ErrorActionPreference = "SilentlyContinue"

    foreach ($dl in $DlsToVerify)
    {        
        Add-LogLine $TraceLogsPath ([string]::Format( "$OperationName Validating DL: {0}", $dl.ExternalDirectoryObjectId) )     
        
        $Global:Error.Clear()
        $members = Get-DistributionGroupMember -Identity $dl.PrimarySmtpAddress.ToString() -ResultSize Unlimited
        if (($Global:Error.Count -gt 0))
        {
            Add-LogLine $ErrorLogsPath ([string]::Format( "Could not find members for the DL: {0}", $dl.ExternalDirectoryObjectId) )
            $errorMessage = $Error -join ";"
            $eligibility = [DlEligibilityType]::NotEligible
            Output-DlEligibility $OutputPath $dl $null $null $LocalizedStrings.UnknownError $eligibility
            $Global:Error.Clear()
            continue
        }        
        Add-LogLine $TraceLogsPath ([string]::Format( "$OperationName - Done getting its members.") )

        $Global:Error.Clear()
        if($IsDCAdmin)
        {
            $owners = Get-DistributionGroup -Identity $dl.PrimarySmtpAddress.ToString() | ForEach-Object { $_.ManagedBy } | Get-SecurityPrincipal -Organization $TenantName
        }
        else
        {
            $owners = Get-DistributionGroup -Identity $dl.PrimarySmtpAddress.ToString() | ForEach-Object { $_.ManagedBy } | Get-SecurityPrincipal
        }
        if (($Global:Error.Count -gt 0))
        {
            Add-LogLine $ErrorLogsPath ([string]::Format( "Could not find owners for the DL: {0}", $dl.ExternalDirectoryObjectId) )
            $errorMessage = $Error -join ";"
            $eligibility = [DlEligibilityType]::NotEligible
            Output-DlEligibility $OutputPath $dl $null $null $LocalizedStrings.UnknownError $eligibility
            $Global:Error.Clear()
            continue
        }     
        Add-LogLine $TraceLogsPath ([string]::Format( "$OperationName - Done getting its owners.") )

        # Get the eligibility or ineligibility reasons for the DL
        $reasonsString = Get-DlReasons $TenantName $dl $members $owners $TraceLogsPath $ErrorLogsPath $OperationName
        if ($reasonsString -ne $null)
        {
            $reasonsList = $reasonsString -as [System.Collections.Generic.List[System.String]]
            Add-LogLine $TraceLogsPath ([string]::Format( "$OperationName - type {0} {1}", $reasonsList.GetType().Name, $reasonsList -join "," ))

            # Get the DL Eligibility category based on reasons
            # Usage: Check Eligibility reasonList AssumeClosedAsPrivate SkipNonUserMailbox
            $category = Get-DlEligibilityBasedOnReasons $reasonsList
        }
        else
        {
            $reasonsList = @("")
            Add-LogLine $TraceLogsPath ([string]::Format( "$OperationName - type {0} {1}", $reasonsList.GetType().Name, $reasonsList -join "," ))
            $category = [DlEligibilityType]::Eligible
        }
        

        #If there was any error in this function other than while in calling EXO cmdlet, then break immediately. Because we do not expect any other errors here and do not know how to handle.
        if (($Global:Error.Count -gt 0))
        {
            break;
        }
        Output-DlEligibility $OutputPath $dl $members $owners $reasonsList $category
    }

    $Global:ErrorActionPreference = $backUpErrorActionPreference
}

function Get-FilteredMailUniversalDl()
{
    param($tenantName, $path, $patternList)

    foreach($pattern in $patternList)
    {
        $nestedDls = Get-DistributionGroup -Organization $tenantName -RecipientTypeDetails MailUniversalDistributionGroup -Filter "(Alias -Like '$pattern') -and (MemberOfGroup -Like '*')"  -ResultSize Unlimited      
        $hashIdsNestedDls = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach($dl in $nestedDls)
        {
            $hashIdsNestedDls.Add($dl.ExternalDirectoryObjectId)
        }
        Get-DistributionGroup -Organization $tenantName -RecipientTypeDetails MailUniversalDistributionGroup -Filter "Alias -Like '$pattern'" -ResultSize Unlimited `
                | ForEach-Object { if($hashIdsNestedDls.Contains($_.ExternalDirectoryObjectId)){ $nesting="NESTED" }else{ $nesting="NONNESTED"}
                                   Add-Content $path ([string]::Format("{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}`t{7}`t{8}`t{9}`t{10}`t{11}`t{12}`t{13}",
                                                     $_.ExternalDirectoryObjectId,
                                                     $_.PrimarySmtpAddress, 
                                                     $_.Alias,
                                                     $_.Name,
                                                     $_.DisplayName,
                                                     $_.MemberJoinRestriction,
                                                     $_.MemberDepartRestriction,
                                                     $_.IsDirSynced,
                                                     $_.HiddenFromAddressListsEnabled,
                                                     $_.ReportToManagerEnabled,
                                                     $_.ReportToOriginatorEnabled,
                                                     $_.ModerationEnabled,
                                                     $_.GrantSendOnBehalfTo.Count,
                                                     $nesting
                                                     ))}

    }    
}

function Output-DlEligibility()
{
    param ($dlEligibilityFilePath, $distributionGroup, $members, $owners, $reasonList, $category)

    if($reasonList.Count -gt 0)
    {
        $reasonListString = ([System.String]::Join(" ",$reasonList))
    }
    else
    {
        $reasonListString = [string]::Empty
    }
    
    $membersSmtp = New-Object System.Collections.Generic.List[System.String]
    foreach($member in $members)
    {
        $membersSmtp.Add($member.PrimarySmtpAddress)
    }

    if($membersSmtp.Count -gt 0)
    {
        $membersSmtpListString = ([System.String]::Join(";",$membersSmtp))
    }
    else
    { 
        $membersSmtpListString = [string]::Empty
    }

    $ownersDn = New-Object System.Collections.Generic.List[System.String]
    foreach($owner in $owners)
    {
        $ownersDn.Add($owner.DistinguishedName)
    }
        
    if($ownersDn.Count -gt 0)
    {
        $ownersDnListString = ([System.String]::Join(";",$ownersDn))
    }
    else
    { 
        $ownersDnListString = [string]::Empty
    }

    $dlData = ([string]::Format("{0}`t{1}`t{2}`t{3}`t{4}`t{5}`t{6}`t{7}`t{8}`t{9}",
                                    $distributionGroup.ExternalDirectoryObjectId,
                                    $distributionGroup.PrimarySmtpAddress,
                                    $distributionGroup.Alias,
                                    $distributionGroup.Name,
                                    $distributionGroup.DisplayName,
                                    $category.ToString(),
                                    $reasonListString,
                                    $membersSmtp.Count,
                                    $membersSmtpListString,
                                    $ownersDnListString                               
                                    ))  

    Add-Content $dlEligibilityFilePath $dlData
}

function Get-DlReasons()
{
    param($TenantName, $dl, $Members, $owners, $TraceLogsPath, $ErrorLogsPath, $OperationName)
    
    $reasonsList = New-Object System.Collections.Generic.List[System.String]    

    if($dl.IsDirSynced -eq $true)
    {
        $reasonsList.Add($LocalizedStrings.IsDirSyncedDl)
    }
    Add-LogLine $TraceLogsPath ([string]::Format( "$OperationName - Done checking DirSync.") )

    if($dl.HiddenFromAddressListsEnabled -eq $true)
    {
        $reasonsList.Add($LocalizedStrings.HalNotSupported)
    }
    Add-LogLine $TraceLogsPath ([string]::Format( "$OperationName - Done checking HiddenFromAddressListsEnabled."))    
   
    if($dl.ModerationEnabled -eq $true)
    {
        $reasonsList.Add($LocalizedStrings.ModerationNotSupported)
    }     
    Add-LogLine $TraceLogsPath ([string]::Format( "$OperationName - Done checking for moderation."))

    if($dl.GrantSendOnBehalfTo -ne $null)
    {
        $typeOfSendOnBehalf = $dl.GrantSendOnBehalfTo.GetType().Name
        if($typeOfSendOnBehalf -eq "String")
        {
            if($dl.GrantSendOnBehalfTo -ne "0")
            {
                $reasonsList.Add($LocalizedStrings.SendOnBehalfNotSupported)
            }
        }
        else
        {
            if($dl.GrantSendOnBehalfTo.Count -ne 0)
            {
                $reasonsList.Add($LocalizedStrings.SendOnBehalfNotSupported)
            }
        }
        Add-LogLine $TraceLogsPath ([string]::Format( "$OperationName - Done checking send on behalf of."))
    }

    $hasChildGroups = Get-DlHasChildGroups $members
    if($hasChildGroups -eq $true)
    {
        $reasonsList.Add($LocalizedStrings.HasChildDls)
    }
    Add-LogLine $TraceLogsPath ([string]::Format( "$OperationName - Done checking for child groups."))
        
    $hasNonUsers = Get-DlHasNonSupportedMemberTypes $members $owners
    if($hasNonUsers)
    {
       $reasonsList.Add($LocalizedStrings.NonSupportedMemberTypes)
    }
    Add-LogLine $TraceLogsPath ([string]::Format( "$OperationName - Done checking for supported member types."))
    
    if($dl.MemberOfGroup -eq "NESTED")
    {
        $reasonsList.Add($LocalizedStrings.IsNested)           
    }
    Add-LogLine $TraceLogsPath ([string]::Format( "$OperationName - Done checking if the dl is a child of another group."))

    $groupType = Get-DlGroupType $dl
    if($groupType -eq [UnifiedGroupType]::Closed) 
    {
        $reasonsList.Add($LocalizedStrings.ClosedGroupNotSupported)
    }
    Add-LogLine $TraceLogsPath ([string]::Format( "$OperationName - Done checking group type of DL."))

    $deliveryStatus = Get-DlHasDeliveryStatusSet $dl
    if($deliveryStatus -eq $true)
    {
        $reasonsList.Add($LocalizedStrings.DeliveryStatusNotSupported)
    }     
    Add-LogLine $TraceLogsPath ([string]::Format( "$OperationName - Done checking Delivery Status."))

    if(($dl.PrimarySmtpAddress -ne $null) -and ($dl.Alias -ne $null))
    {
        $indexOfDomainSep = $dl.PrimarySmtpAddress.LastIndexOf("@")
        $localOfSmtp = $dl.PrimarySmtpAddress.SubString(0,$indexOfDomainSep)
        if($localOfSmtp.StartsWith("MigratedDl_") -and $dl.Alias.StartsWith("MigratedDl-"))
        {
           $reasonsList.Add($LocalizedStrings.DlAlreadyMigrated)
        }
    }
    Add-LogLine $TraceLogsPath ([string]::Format( "$OperationName - Done checking if the DL is already migrated."))

    return $reasonsList
}

function New-UnifiedGroupFromDistributionGroup()
{
    param (
        [parameter(Mandatory=$true)]
        $DlsToMigrate,

        [parameter(Mandatory=$true)]
        [string] $Organization,

        [Parameter(Mandatory=$true)]
        [bool] $ConvertClosedDLToPrivateGroup,

        [Parameter(Mandatory=$true)]
        [bool] $DeleteDLAfterMigration,

        [parameter(Mandatory=$true)]
        [string] $OutputPath,

        [parameter(Mandatory=$true)]
        [string] $TraceLogsPath,

        [parameter(Mandatory=$true)]
        [string] $ErrorLogsPath,
        
        [Parameter(Mandatory=$False)]
        [bool] $IsDcAdmin = $False
    )   

    $backUpErrorActionPreference = $Global:ErrorActionPreference
    $Global:ErrorActionPreference = "SilentlyContinue"
   
    foreach($dl in $DlsToMigrate)
    {        
        $migrationOutputData = ([string]::Format("{0}`t{1}`t{2}`t{3}`t{4}`t{5}", 
                                        $dl.ExternalDirectoryObjectId,
                                        $dl.PrimarySmtpAddress,
                                        [string]::Empty,
                                        [string]::Empty,
                                        [DlMigrationStatus]::Running,
                                        [string]::Empty))

        Add-Content $OutputPath $migrationOutputData        
        Add-LogLine $TraceLogsPath ([string]::Format("Migrating DL: {0} {1}", $dl.PrimarySmtpAddress, $dl.ExternalDirectoryObjectId))
        if($IsDcAdmin)
        {
            $ug = New-UnifiedGroup -Organization $Organization -DeleteDLAfterMigration:$DeleteDLAfterMigration -ConvertClosedDLToPrivateGroup:$ConvertClosedDLToPrivateGroup -DLIdentity $dl.PrimarySmtpAddress
        }
        else
        {
            $ug = New-UnifiedGroup -DeleteDLAfterMigration:$DeleteDLAfterMigration -ConvertClosedDLToPrivateGroup:$ConvertClosedDLToPrivateGroup -DLIdentity $dl.PrimarySmtpAddress        
        }

        # Compute the status of migration form the output and errors.
        # Failed -- ug null, error
        # Failed Action Needed -- ug null, Action needed exception
        # Success -- ug value and smtp matches
        # Success Action Needed -- ug value, error with Action needed exception
        # Not Eligible - $error[0].CategoryInfo.Reason
        # Unknown Error

        $status = "NONE"
        $errorMessage = [string]::Empty;
        
        if($Global:Error.Count -gt 0)
        {
            $errorMessage = $Global:Error -join " "
            $errorCategories = $Global:Error.CategoryInfo.Reason -join " "            
            Add-LogLine $TraceLogsPath ($errorMessage + $errorCategories)
            if($Global:Error[0].CategoryInfo.Reason -eq "DgNotEligibleForMigrationToUgException")
            {
                $status = [DlMigrationStatus]::NotEligible
            }
            elseif($errorCategories.Contains("DgMigrationToUgActionRequiredException"))
            {
                if($ug -eq $null)
                {
                    $status = [DlMigrationStatus]::FailureActionRequired  
                }
                else
                {
                    $status = [DlMigrationStatus]::SuccessActionRequired
                }
            }
            else
            {
                $status = [DlMigrationStatus]::Failure  
            }
        }
        else
        {
            if($ug -ne $null)
            {
                $status = [DlMigrationStatus]::Success
            }
            else
            {
                $status = [DlMigrationStatus]::UnknownError
            }
        }

        $errorMessage = $errorMessage.Replace("`n"," ")
        $errorMessage = $errorMessage.Replace("`r"," ")

        #DL EOI-> DL SMTP -> UG EOI -> UGSMTP -> Status -> Errors
        $migrationOutputData = ([string]::Format("{0}`t{1}`t{2}`t{3}`t{4}`t{5}", 
                                        $dl.ExternalDirectoryObjectId,
                                        $dl.PrimarySmtpAddress,
                                        $ug.ExternalDirectoryObjectId,
                                        $ug.PrimarySmtpAddress,
                                        $status,
                                        $errorMessage))

        $outputFileContent = Get-Content $OutputPath
        $outputFileContentList = $outputFileContent -as [System.Collections.Generic.List[System.String]]
        $outputFileContentList[$outputFileContent.Count - 1] = $migrationOutputData

        Set-Content $OutputPath $outputFileContentList
        
        $Global:Error.Clear();
    }
    $Global:ErrorActionPreference = $backUpErrorActionPreference
}

function Merge-FileContentFromIntermediate()
{
    param($parentFilePath)

    if((Test-Path $parentFilePath) -eq $True)
    {
        $IntermediateFilePath1 = Get-OutputPathForThread $parentFilePath 0 $true
        if((Test-Path $IntermediateFilePath1) -eq $True)
        {
            $IntermediateContent1 = Get-Content $IntermediateFilePath1
            Add-Content $parentFilePath $IntermediateContent1
            Remove-Item $IntermediateFilePath1
        }

        $IntermediateFilePath2 = Get-OutputPathForThread $parentFilePath 1 $true
        if((Test-Path $IntermediateFilePath2) -eq $True)
        {
            $IntermediateContent2 = Get-Content $IntermediateFilePath2
            Add-Content $parentFilePath $IntermediateContent2
            Remove-Item $IntermediateFilePath2
        }

        $IntermediateFilePath3 = Get-OutputPathForThread $parentFilePath 2 $true
        if((Test-Path $IntermediateFilePath3) -eq $True)
        {
            $IntermediateContent3 = Get-Content $IntermediateFilePath3
            Add-Content $parentFilePath $IntermediateContent3
            Remove-Item $IntermediateFilePath3
        }
    }
}

<# --------------------------------------------------------------------------------------------------------------------------------------------------------------------------
DL ineligibility reasons
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------#> 
$LocalizedStrings = $null
Import-LocalizedData -BindingVariable LocalizedStrings -FileName DlMigration.strings.psd1 -BaseDirectory $env:PSModulePath.Split(";")[0]

<# --------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Export members
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------#> 

Export-ModuleMember -Function Add-LogLine
Export-ModuleMember -Function Publish-DlEligibilityForGroups
Export-ModuleMember -Function Get-FilteredMailUniversalDl

Export-ModuleMember -Function Get-DlGroupType
Export-ModuleMember -Function Get-DlHasDeliveryStatusSet
Export-ModuleMember -Function Get-DlHasChildGroups
Export-ModuleMember -Function Get-DlHasNonSupportedMemberTypes
Export-ModuleMember -Function Get-DlEligibilityBasedOnReasons
Export-ModuleMember -Function Get-OutputPathForThread

Export-ModuleMember -Function New-UnifiedGroupFromDistributionGroup
Export-ModuleMember -Function Merge-FileContentFromIntermediate
# SIG # Begin signature block
# MIIdrAYJKoZIhvcNAQcCoIIdnTCCHZkCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUqSJuqn2nWh9oGF5RRhT9qpzl
# IAWgghhkMIIEwzCCA6ugAwIBAgITMwAAAJqamxbCg9rVwgAAAAAAmjANBgkqhkiG
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
# bWrJUnMTDXpQzTGCBLIwggSuAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25pbmcg
# UENBIDIwMTECEzMAAABkR4SUhttBGTgAAAAAAGQwCQYFKw4DAhoFAKCBxjAZBgkq
# hkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGC
# NwIBFTAjBgkqhkiG9w0BCQQxFgQUrdtE0J9a9YPPgOtMRnIKw8TK2akwZgYKKwYB
# BAGCNwIBDDFYMFagLoAsAEQAbABNAGkAZwByAGEAdABpAG8AbgBNAG8AZAB1AGwA
# ZQAuAHAAcwBtADGhJIAiaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL2V4Y2hhbmdl
# IDANBgkqhkiG9w0BAQEFAASCAQAJmmwJ/tFJ2tMnn+DvYI+PtQ/VG7ms/t7Xl4nb
# DRfAJP0lyQUJ8wjCbEc5EhhOz5VwFXuOQYL7rnJuA606AsiEOFjGkCrYA9dA8YED
# gqNt1JUj6bKEgTgoI/r/AgmGrQjFMNNfCrSWECE4rM8mkORK/Pvqr+NByYI7FCGi
# X4e0ybITvueRstKjruZ3zeDHScMsHwZVaZlegWGXHFClZnKv0LfYM5HH5uH95NAU
# YMtmVXgsFWreZWDs8qh28aZYdmbjC5TFx3+YikJhwP5GRbpLh8/UtWD9l5Nbuf3E
# 3AOTyNJ4seioF9P1Os7z1T372ogZEwQdCXApRRQrxkMeygLloYICKDCCAiQGCSqG
# SIb3DQEJBjGCAhUwggIRAgEBMIGOMHcxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xITAfBgNVBAMTGE1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQQIT
# MwAAAJqamxbCg9rVwgAAAAAAmjAJBgUrDgMCGgUAoF0wGAYJKoZIhvcNAQkDMQsG
# CSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMTYwODEyMDM0NzI3WjAjBgkqhkiG
# 9w0BCQQxFgQUirCVjGaqFaNgkT1HQSLq6lY1Y/wwDQYJKoZIhvcNAQEFBQAEggEA
# ZGUXNzySEFtP/K7on8rORc6d+8sjMx9/xZgRHHBU8g2aTmRmQiZqo3dD8ROAQekw
# z3cawRapO4kQewCzb3pvrohTORgM7dfy9XonqTaDCQkJecJoHy23mnIIcnMVUqQ3
# SHORsh/J4huUt4dFbaf2E93+fXSZoHkqW/8RHrxS3Q/FUozsZFLcDa3SSq7hWnjM
# kprN9z1eyvP7PSlPjhfqYhyfH9yLc7+o3POQcsifD2IeOgOsJuG1VAATOmLfoN+r
# SH8VERdsR6rvZ7mLsh61bQ3au7en+W723mEI+bs5kRaL+Gg4yO3uelb82Fo7aZxV
# 6rOMHEUZzOzJ63vCM4JSaw==
# SIG # End signature block
