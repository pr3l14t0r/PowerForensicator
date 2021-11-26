function New-Init {
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $VM,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ImageDirectory #ToDo: Add explanation
    )

    # for the logging function
    $Component = "New-Init"
    
    # Verify that the ImageDirectory folder is existing
    Write-VBox4PwshLog -Component $Component -Message ("Verifying path <"+$ImageDirectory+">...") -Level Verbose
    if(-not (Test-Path -Path $ImageDirectory -PathType Container))
    {
        Write-VBox4PwshLog -Component $Component -Message ("The path does not exist. Creating it now") -Level Verbose
        $null = New-Item -Path $ImageDirectory -ItemType Directory -Force -ErrorAction Stop
    }

    # parallelize the steps needed for each VM
    $VM |ForEach-Object -Parallel {

        # when running in parallel, the processes sometimes can't access the logfiles simultaneously. Let's add a few milliseconds of wait time
        Start-Sleep -Milliseconds (Get-Random -Minimum 10 -Maximum 1000)
        
        $VerbosePreference = $using:VerbosePreference

        $VMIdentifier = $PSItem

        Import-Module VBox4Pwsh

        # Save the VMs State
        Save-VBoxVMState -VMIdentifier $VMIdentifier

        #Create Snapshot and name it "INIT"
        New-VBoxVMSnapshot -VMIdentifier $VMIdentifier -SnapshotName "INIT"

        #Export the INIT File 
        # Clone the whole medium which is in state of INIT Snapshot
        $CurrentSnapshot = Get-VBoxVMSnapshot -VMIdentifier $VMIdentifier | Where-Object {$_.IsCurrent -eq $true}
        $HDD = Get-VboxHDDs | Where-Object {$_.InusebyVMs -like ("*"+$VMIdentifier+"*"+$CurrentSnapshot.Name+"*")}

        $RAWFileName = ([System.IO.Path]::Combine($using:ImageDirectory,([string]::Concat($VMIdentifier,'_','INIT','.raw'))))
        Clone-VBoxDiskMedium -Source ($HDD.UUID) -Target $RAWFileName -Format RAW

        # Creating now the fiwalk xml
        New-FiwalkXML -ImageFilePath $RAWFileName

        # close the cloned medium.
        # This will remove the disk entry out of virtualbox while keeping the raw file that has been exported in the previous step.
        #Close-VBoxDiskMedium -Medium $RAWFileName
    }
}