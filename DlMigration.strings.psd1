ConvertFrom-StringData @'
###PSLOC
UnknownError = An unknown error has occurred. 
ClosedGroupNotSupported = The Join and Depart restrictions setting on this distribution list does not have a corresponding type in Office 365 Groups. If you continue, the DL will be converted to a Private group.
IsDirSyncedDl = This distribution list is not cloud managed.
HalNotSupported = This distribution list is hidden from the address list.
DeliveryStatusNotSupported = This distribution list has a custom delivery status notification set. 
ModerationNotSupported = This is a moderated distribution list.
SendOnBehalfNotSupported = This distribution list has send on behalf permissions.  
HasChildDls = This distribution list has child groups.
IsNested = This distribution list is a child of another group.
NonSupportedMemberTypes = This distribution list has member types which are not supported in Office 365 groups.
DlAlreadyMigrated = Looks like this distribution list is already migrated to an Office 365 group.
ConfirmationYesOption = &Yes
ConfirmationNoOption = &No
ExitFromScript = Exit from the script.
FilesWillBeOverWritten = Output files in the working directory will be overwritten.
DlEligibilityPopUpTitle = DL Eligibility Script
DlEligibilityOutputOverwrite = DL Eligibility output files: 'DlEligibilityList' and 'MailUniversalDistributionList' already exist in the directory. Do you still want to continue and overwrite these files?
ParamValidateUseTogether = You cannot specify parameters {0} together.
ParamValidateDcAdminMultipleConnections = DC Admin cannot use multiple connections.
ParamValidateSpecifyParam = Please input the value for parameter {0} and run the command again.
ParamValidateDcAdminNotSupported = DL Migration is not yet supported for DC Admin.
Status = STATUS:
Started = Started
Finished = Finished
GetAllDls = Getting all distribution lists in the tenant based on filters specified for alias.
ErrorFetchingDls = An error occurred when fetching all the distribution lists. Look at the error logs for more details. Path:
StatusFinishedIdentifyingDls = STATUS: Finished identifying the list of DLs to check for Eligibility in this run. Input DL count: {0}, Dls to verify: {1}, Processed DL count: {2}.
StatusStartedIdentifyingDls = identifying the list of DLs to check for Eligibility in this run.
StatusInputListHasNoData = No distribution lists to process.
StatusHeaderNotMatching = Header of the input file is not matching the expected header. 
RerunScriptWithout = Please run the script again without using
BatchStart = {0} Processing batch starting {1} ending {2}.
BatchFinish = {0} Finished processing batch starting {1} ending {2}. Processed Count: {3}, Succeeded Count: {4}.
ScriptSuccessful = Script completed successfully.
ScriptFailed = An error occurred while processing, stopping the script. Check logs for more info. Path:
SkippingDl = Skipping distribution list {0} with SMTP {1} because the number of columns are not matching.
DlMigrationPopUpTitle = DL Migration Script
DlMigrationOutputFile = DL Migration output files: 'MigrationOutput' already exists in the directory. Do you still want to continue and overwrite the file?
DlIdentifyingDlsToMigrate = identifying DLs to be migrated.
DlIdentifyingDlsToMigrateFinish = STATUS: Finished identifying DLs to be migrated. Input DL count: {0},  Dls To Migrate: {1}, Processed DL count: {2}.
NoDlsToMigrate = There are no distribution lists to migrate.
ContinueWithNextBatchPrompt = Do you want to continue migrating the next batch starting {0} ending {1} ?
ContinueNextBatch = Migrate the next batch of DLs.
###PSLOC
'@