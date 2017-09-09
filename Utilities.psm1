$Global:CurrentLocation = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$Global:LogFolder = "$Global:CurrentLocation\Logs"

Function Create-Folder
{
    param(
           [parameter(Mandatory=$true)][string] $FolderName
         )
    
    #If folder does not exist create it
    if(-not (Test-Path $FolderName))
    {
        New-Item -ItemType directory -Path $FolderName
    }
}

Function Write-Log
{
   param(
          [parameter(Mandatory=$true)][string]$Message
        )

   Create-Folder -FolderName $Global:LogFolder
   $timestamp = Get-Date -Format o | foreach {$_ -replace ":", "-"}
   $Logfile = "$Global:LogFolder\log.txt"
   Add-content $Logfile -value "$timestamp $message"  
}

Function Show-ErrorMessage
{
    param(
           [parameter(Mandatory=$true)][string]$Message
         )

    Write-Host $Message -ForegroundColor Red
    Write-Log $Message
}

Function Show-SuccessMessage
{
    param(
           [parameter(Mandatory=$true)][string]$Message
         )

    Write-Host $Message -ForegroundColor Green
    Write-Log $Message
}

Function Backup-File
{
    Param ([parameter(Mandatory=$true)][string]$FileToBackup,
           [parameter(Mandatory=$true)][string]$BackupName,
           [parameter(Mandatory=$true)][string]$BackupFolder)

    Create-Folder -FolderName $BackupFolder

    #Initialize variables
    $timestamp = Get-Date -Format o | foreach {$_ -replace ":", "-"}

    #Define Backup Filename
    $BackupFile = "$BackupFolder\$BackupName.$timestamp.bak";

    #Backup
    Copy-Item $FileToBackup $BackupFile

    Show-SuccessMessage "Backup file has been created: $BackupFile"
}

Function Rollback-File
{
    Param ([parameter(Mandatory=$true)][string]$FileToRestore,
           [parameter(Mandatory=$true)][string]$BackupName,
           [parameter(Mandatory=$true)][string]$BackupFolder)

    #Search for all the backup files using $BackupName
    $SearchTerm =  "$BackupName*.bak"
    $FirstBackupFile = Get-Childitem –Path $BackupFolder -Include $SearchTerm -File -Recurse | Select-Object -First 1

    #Is there any backup?
    if(($FirstBackupFile.count -gt 0) -and (Test-Path $FirstBackupFile[0]))
    {
        #Yes - Restore the latest backup file
        Show-SuccessMessage "Restoring the latest backup file: $FirstBackupFile";

        Copy-Item $FirstBackupFile[0] $FileToRestore

        Show-SuccessMessage "Restore successful: $FirstBackupFile"
    }
    else
    {
        #No - There is no backup file to restore
        Show-ErrorMessage "$BackupName was not found."
    }
    exit
}

Function Change-AttributeValue
{
    param(
           [parameter(Mandatory=$true)][xml] $XmlContent,
           [parameter(Mandatory=$true)][string] $NodeLocation,
           [parameter(Mandatory=$true)][string]$AttributeName,
           [parameter(Mandatory=$true)][string]$AttributeValue
         )

    if($NodeLocation -eq "")
    {
        Show-ErrorMessage "NodeLocation can't be empty"
        exit
    }

    if($AttributeName -eq "")
    {
        Show-ErrorMessage "AttributeName can't be empty"
        exit
    }
	
	if($AttributeValue -eq "")
    {
        Show-ErrorMessage "AttributeValue can't be empty"
        exit
    }

    $XmlNode = $XmlContent.SelectSingleNode($NodeLocation)

    $XmlNode.SetAttribute($AttributeName, $AttributeValue);

    Show-SuccessMessage "Attribute $AttributeName has been set to $AttributeValue"

}

Function Change-TextValue
{
    param(
           [parameter(Mandatory=$true)][string] $NodeLocation,
           [parameter(Mandatory=$true)][string]$TextValue
         )

    if($NodeLocation -eq "")
    {
        Show-ErrorMessage "NodeLocation can't be empty"
        exit
    }

    $XmlNode = $XmlToPatch.SelectSingleNode($NodeLocation)

    $OldText = $XmlNode.'#text';
    $XmlNode.'#text' = $TextValue;

    Show-SuccessMessage "Value $OldText has been replaced with $TextValue"
}

Function Remove-Node
{
    param(
           [parameter(Mandatory=$true)][xml] $XmlContent,
           [parameter(Mandatory=$true)][string]$NodeToRemoveLocation
         )

    $NodeToRemove = $XmlContent.SelectSingleNode($NodeToRemoveLocation)
    $NodeToRemoveParent = $NodeToRemove.ParentNode
    $NodeToRemoveParent.RemoveChild($NodeToRemove)
}

Function Add-Node
{
    param(
           [xml] $XmlContent,
           [string]$NodeToAddLocation,
           [string]$NodeContent
         )

    $ParentNodeForAddition = $XmlContent.SelectSingleNode($NodeToAddLocation)
    $XmlNodeContentToAdd = [xml] $NodeContent
    $nodeToAddImported = $XmlContent.ImportNode($XmlNodeContentToAdd.DocumentElement, $true)
    $ParentNodeForAddition.AppendChild($nodeToAddImported)
}

Function Read-Node
{
    param(
           [xml] $XmlContent,
           [string]$NodeLocation
         )

    $XmlNode = $XmlContent.SelectSingleNode($NodeLocation)
	return $XmlNode.OuterXml
}

Function Save-XmlFile
{
    param(
           [xml]$XmlContent,
           [string]$XmlLocation
         )
    $XmlContent.Save($XmlLocation);
    Show-SuccessMessage "File saved successfully $XmlLocation"
}

Function Replace-Files
{
    param(
            [string] $PatchFolder = $Global:CurrentLocation + "\Patch",
            [string] $BackupFolder = $Global:BackupFolder,
            [parameter(Mandatory=$true)][string] $TargetFolder = "",
            [string] $TargetFiles = "*.*"
         )

    #Validate TargetFolder
    if(-not (Test-Path $TargetFolder))
    {
        Show-ErrorMessage "Target folder does not exist"
        exit
    }

    if(-Not (Test-Path $BackupFolder))
    {
        New-Item $BackupFolder -type directory
    }

    #Get all the files
    $FilesInTargetFolder = Get-ChildItem -Path $TargetFolder -Filter $TargetFiles -Recurse -Force
    $FilesInPatchFolder = Get-ChildItem -Path $PatchFolder -Filter $TargetFiles -Recurse -Force

    foreach ($FileInPatchFolder in $FilesInPatchFolder) 
    {
        foreach ($FileInTargetFolder in $FilesInTargetFolder) 
        {
            #If it's not a directory
            if($FileInTargetFolder.Attributes -ne ‘Directory’)
            {
                #If the file to replace if found
                if($FileInTargetFolder.Name -eq $FileInPatchFolder.Name)
                {
                    #Create Backup Subfolder
                    $BackupSubfolder = $BackupFolder + $FileInTargetFolder.Directory.FullName.Replace($TargetFolder, "")

                    if(-Not (Test-Path $BackupSubfolder))
                    {
                        New-Item $BackupSubfolder -type directory
                    }

                    #Create Backup File
                    Copy-Item $FileInTargetFolder.FullName $BackupSubfolder

                    #Replace File
                    Copy-Item $FileInPatchFolder.FullName $FileInTargetFolder.FullName

                    #Check source and destination file version
                    if([System.Diagnostics.FileVersionInfo]::GetVersionInfo($FileInPatchFolder.FullName).FileVersion -ne [System.Diagnostics.FileVersionInfo]::GetVersionInfo($FileInTargetFolder.FullName).FileVersion)
                    {
                        Write-Error "Source and Destination File Versions do not match"
                    }
                }
            }
        }
    }

    Show-SuccessMessage "Files were replaced successfully"
}

Function Create-RemoteFolder
{
    param(
           [parameter(Mandatory=$true)][string] $FolderName,
           [parameter(Mandatory=$true)][string] $ServerName,
           [parameter(Mandatory=$true)][System.Management.Automation.PSCredential] $AuthCredentials
         )

	Invoke-Command -ComputerName $ServerName -authentication credssp -credential $AuthCredentials -scriptblock {
			
			param([String]$FolderName)
		
            if(-not (Test-Path $FolderName))
            {
			    New-Item $FolderName –type directory
            }

    } -ArgumentList $FolderName
}

Function Copy-RemoteFolder
{

    param(
           [parameter(Mandatory=$true)][string] $FolderToCopy,
           [parameter(Mandatory=$true)][string] $TargetFolder,
           [parameter(Mandatory=$true)][string] $ServerName,
           [parameter(Mandatory=$true)][System.Management.Automation.PSCredential] $AuthCredentials
         )

    Invoke-Command -ComputerName $ServerName -authentication credssp -credential $AuthCredentials -scriptblock {
			
			param([String]$FolderToCopy,
                  [String]$TargetFolder)
		
            if(-not (Test-Path $TargetFolder))
            {
			    Copy-Item -Path $FolderToCopy -Destination $TargetFolder -Recurse 
            }

    } -ArgumentList $FolderToCopy, $TargetFolder
}

Function Copy-Folder
{

    param(
           [parameter(Mandatory=$true)][string] $FolderToCopy,
           [parameter(Mandatory=$true)][string] $TargetFolder
         )

        if(-not (Test-Path $TargetFolder))
        {
			Copy-Item -Path $FolderToCopy -Destination $TargetFolder -Recurse 
        }
}

Function Validate-String
{
    param(
           [string] $ActualValue,
           [string] $ExpectedValue
         )

    if($ActualValue -ne $ExpectedValue) 
    {
        Show-ErrorMessage -Message "Validation Failed"
        Show-ErrorMessage -Message "ActualValue: $ActualValue"
        Show-ErrorMessage -Message "ExpectedValue:$ExpectedValue"
    }
    else
    {
        Show-SuccessMessage -Message "Validation Sucessful"
        Show-SuccessMessage -Message "ActualValue: $ActualValue"
        Show-SuccessMessage -Message "ExpectedValue:$ExpectedValue"
    }
}

Function Execute-LocalScript
{
	    param(
           [parameter(Mandatory=$true)][string] $Script,
           [parameter(Mandatory=$true)][string] $Parameters
         )

	Invoke-Expression "$Script $Parameters"
}

Function Execute-RemoteScript
{
	    param(
           [parameter(Mandatory=$true)][string] $ServerName,
		   [parameter(Mandatory=$true)][string] $Script,
           [parameter(Mandatory=$true)][string] $Parameters,
           [parameter(Mandatory=$true)][System.Management.Automation.PSCredential] $AuthCredentials
         )

	    Invoke-Command -ComputerName $ServerName -authentication credssp -credential $AuthCredentials -scriptblock {
				
        param([String]$Script,
              [String]$Parameters)

        Invoke-Expression "$Script $Parameters"

        } -ArgumentList $Script, $Parameters
}