function Invoke-ActionStateFileExport {
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $VM,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ImageDirectory, #ToDo: Add explanation

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ActionName,

        [Parameter()]
        [int]
        $MinutesToWait = 0, #ToDo: Add help information

        [Parameter()]
        [AllowNull()]
        [switch]
        $KeepExportedImageFile,

        # This switch tells the cmdlet to use the locally installed fiwalk executable instead of the dockerized one. WARNING! You need make sure that fiwalk is located in PATH and usable!
        [Parameter()]
        [AllowNull()]
        [switch]
        $LocalFiwalk,

        # This switch tells the cmdlet to use the locally installed python module instead of the dockerized one
        [Parameter()]
        [AllowNull()]
        [switch]
        $LocalPython
    )

    # for the logging function
    $Component = "Invoke-ActionStateFileExport"

    # Verify that the ImageDirectory folder is existing
    Write-VBox4PwshLog -Component $Component -Message ("Verifying path <"+$ImageDirectory+">...") -Level Verbose
    if(-not (Test-Path -Path $ImageDirectory -PathType Container))
    {
        Write-VBox4PwshLog -Component $Component -Message ("The path does not exist. Creating it now") -Level Verbose
        $null = New-Item -Path $ImageDirectory -ItemType Directory -Force -ErrorAction Stop
    }

    # In case that "LocalFiwalk" has been set, make sure that it is available
    if($LocalFiwalk){
        if(-not (Invoke-Process -FilePath "fiwalk")){Write-VBox4PwshLog -Message ("The <fiwalk> binary can not be invoked! Please make sure that the binary is reachable through your <PATH> environment variable.") -Component $Component -Level Warning; break}
    }

    # Todo: check prerequisites for local python.
    <#
        # check the python version 
        # check whether idifference2.py is there (path?!)
        # If not, try to use the shipped one within this module
    #>

    # parallelize the steps needed for each VM
    $VM | ForEach-Object -Parallel {

        $StartTime = [datetime]::Now

        # when running in parallel, the processes sometimes can't access the logfiles simultaneously. Let's add a few milliseconds of wait time
        Start-Sleep -Milliseconds (Get-Random -Minimum 10 -Maximum 2000)
        $VerbosePreference = $using:VerbosePreference

        $VMIdentifier = $PSItem

        # Importing the VirtualBox for PowerShell module
        Import-Module VBox4Pwsh

        Write-VBox4PwshLog -VM $VMIdentifier -Component $using:Component -Message ("Exporting the RAW disk image and analyzing the evidences from action <"+$using:ActionName+"> of VM <"+$VMIdentifier+"> now!")

        # Save the VMs State
        Save-VBoxVMState -VMIdentifier $VMIdentifier

        #Create Snapshot
        New-VBoxVMSnapshot -VMIdentifier $VMIdentifier -SnapshotName $using:ActionName

        #Export the Action file 
        # Clone the whole (disk)-medium which is in state of current Snapshot
        $CurrentSnapshot = Get-VBoxVMSnapshot -VMIdentifier $VMIdentifier | Where-Object {$_.IsCurrent -eq $true}
        $HDD = Get-VboxHDDs | Where-Object {$_.InusebyVMs -like ("*"+$VMIdentifier+"*"+$CurrentSnapshot.Name+"*")}

        $filename = ([string]::Concat($VMIdentifier,'_',$using:ActionName,'.raw'))
        $RAWFileName = ([System.IO.Path]::Combine($using:ImageDirectory,$filename))

        # pre-check if a raw-file is still registered in VirtualBox. If so, close it!
        Write-VBox4PwshLog -VM $VMIdentifier -Component $using:Component -Message ("Check if a medium is already or still registered for VM <"+$VMIdentifier+"> at path <"+$RAWFileName+">...") -Level Verbose
        if($null -ne (Get-VboxHDDs |Where-Object {$_.Location -eq $RAWFileName}))
        {
            # There is still a medium registered where the location equals the new RAWFile ones. We'll unregister the medium so that we can proceed!
            Write-VBox4PwshLog -VM $VMIdentifier -Component $using:Component -Message ("There is an already registered medium for VM <"+$VMIdentifier+"> at path <"+$RAWFileName+">! This will be removed in order to export the new one!") -Level Verbose
            Close-VBoxDiskMedium -Medium $RAWFileName -Delete
        }
        else{Write-VBox4PwshLog -VM $VMIdentifier -Component $using:Component -Message "No registered medium found!" -Level Verbose}

        # Clone the medium now!!
        Clone-VBoxDiskMedium -Source ($HDD.UUID) -Target $RAWFileName -Format RAW

        Write-VBox4PwshLog -VM $VMIdentifier -Component $using:Component -Message ("Succesfully exported file <"+$RAWFileName+">!") -Level Verbose

        # Now invoke the differential analysis
        # First, fetch full qualifiied path of INIT.raw
        $INITRawFile = Get-VboxHDDs | Where-Object {$_.Location -like ("*"+$VMIdentifier+"_INIT*")} |Select-Object -ExpandProperty Location

        # Verify the path of INIT raw file
        if([string]::IsNullOrEmpty($INITRawFile)){Write-VBox4PwshLog -VM $VMIdentifier -Component $using:Component -Message ("No INIT RAW-File has been found for VM <"+$VMIdentifier+">") -Level Error;break}
        if(-not (Test-Path -Path $INITRawFile -PathType Leaf)){Write-VBox4PwshLog -VM $VMIdentifier -Component $using:Component -Message ("The filepath <"+$VMIdentifier+"> could not be verified!") -Level Warning;break}

        Write-VBox4PwshLog -VM $VMIdentifier -Component $using:Component -Message ("Succesfully fetched INIT RAW file <"+$INITRawFile+">") -Level Verbose

        # Now invoke fiwalk and idifference2.py based on the environmental setting
        if($using:LocalFiwalk -and (-not $using:LocalPython))
        {
            # Use the local binary of fiwalk but execute idifference2.py in a dockerized container!
            Write-VBox4PwshLog -VM $VMIdentifier -Component $using:Component -Message ("Locally installed <fiwalk> binary will be used.") -Level Verbose
            
            # fiwalk will generate XML files. Those files will be stored within the directory of the rawfile. 
            $INITXmlPath = [System.IO.Path]::ChangeExtension($INITRawFile,"xml")

            $ActionXmlPath = [System.IO.Path]::ChangeExtension($RAWFileName,"xml")

            # that given, create needed XMLs. 
            # Hint (#todo): This one checks if there is already an XML file for INIT. If so, it won't get recreated.
            if(-not (Test-Path $INITXmlPath))
            {
                Write-VBox4PwshLog -Message ("Fiwalk-XML has not yet been created now from image <"+$INITRawFile+">. This will be done now!") -VM $VMIdentifier -Component $using:Component -Level Verbose
                $ret = Invoke-Process "fiwalk" -ProcessArguments ("-X",$INITXmlPath,$INITRawFile)
                if($ret.ExitCode -ne 0)
                {
                    Write-VBox4PwshLog -Message ("The <fiwalk> process did not finish succesfully!") -VM $VMIdentifier -Component $using:Component -Level Warning
                    Write-VBox4PwshLog -Message ("STDOut: " + $ret.stdout) -VM $VMIdentifier -Component $using:Component -Level Warning -Indent 4
                    Write-VBox4PwshLog -Message ("STDErr: " + $ret.stderr) -VM $VMIdentifier -Component $using:Component -Level Error -Indent 4
                    break
                }
                else
                {
                    Write-VBox4PwshLog -Message ("Succefully created fiwalk-xml from image <"+$INITRawFile+">") -VM $VMIdentifier -Component $using:Component -Level Verbose
                }
            }

            # create ACTION xml
            Write-VBox4PwshLog -Message ("Creating fiwalk-xml now from image <"+$RAWFileName+">") -VM $VMIdentifier -Component $using:Component -Level Verbose
            $ret = Invoke-Process "fiwalk" -ProcessArguments ("-X",$ActionXmlPath,$RAWFileName)
            if($ret.ExitCode -ne 0)
            {
                Write-VBox4PwshLog -Message ("The <fiwalk> process did not finish succesfully!") -VM $VMIdentifier -Component $using:Component -Level Warning
                Write-VBox4PwshLog -Message ("STDOut: " + $ret.stdout) -VM $VMIdentifier -Component $using:Component -Level Warning -Indent 4
                Write-VBox4PwshLog -Message ("STDErr: " + $ret.stderr) -VM $VMIdentifier -Component $using:Component -Level Error -Indent 4
                break
            }
            else {
                Write-VBox4PwshLog -Message ("Succefully created fiwalk-xml from image <"+$RAWFileName+">") -VM $VMIdentifier -Component $using:Component -Level Verbose
            }

            # now run idifference2.py
            if($using:LocalPython){
                #todo: IMPLEMENT THIS!!!
            }
            else
            {

                # prepare and modify paths, cause the docker image is UNIX based
                $basePath = Split-Path -Path $INITXmlPath -Parent
                $relativePathToActionXML = $ActionXmlPath -replace ([regex]::Escape($basePath),'') -replace ([regex]::Escape('\'),'/')
                if($relativePathToActionXML.StartsWith('/')){$relativePathToActionXML = $relativePathToActionXML.TrimStart('/','\')}

                # generate the name of the target iDiff file (the file that will be created from idifference2.py)
                $idiffPath = [System.IO.Path]::Join((Split-Path -Path $relativePathToActionXML -Parent),([string]::Concat($VMIdentifier,'_',$using:ActionName,'.idiff')))
                $idiffPath = $idiffPath -replace ([regex]::Escape('\'),'/')

                $DockerArgs = @(
                    "run"
                    "--rm"
                    "-v"
                    ([string]::Concat($basePath,':','/images'))
                    "pr3l14t0r/forensics:idifference2"
                    "-x"
                    $idiffPath
                    ([System.IO.Path]::GetFileName($INITXmlPath))
                    $relativePathToActionXML
                )
            }
        }
        else
        {
            # Docker will be used to both invoke fiwalk and idifference2.py.
            # To be technically correct: idifference2.py will be invoked with other parameters so that the *.raw images do get processed directly.
            <# 
                The INIT Raw-File will always be located in parent-directory of an Image from the current round
                That means that the Parent-Directory of INIT.raw will be the base
                iDifference2.py will then be invoked with smth like this: idifference2.py -x ActionName/Action.iDiff INIT.raw ActionName/Action.raw
            #>
            # If there is an XML file of that INIT raw file, prefer the XML file over the raw file. 
            $INITFileName = $INITRawFile
            if(Test-Path -Path ([System.IO.Path]::ChangeExtension($INITRawFile,"xml")) -PathType Leaf)
            {
                $INITFileName = ([System.IO.Path]::ChangeExtension($INITRawFile,"xml"))
                Write-VBox4PwshLog -Message ("Found an XML file for the INIT raw image at path <"+$INITFileName+">. This one will be preferred!") -VM $VMIdentifier -Component $using:Component -Level Verbose
            }

            $basePath = Split-Path -Path $INITFileName -Parent
            $relativePathToActionRAWFile = $RAWFileName -replace ([regex]::Escape($basePath),'') -replace ([regex]::Escape('\'),'/')
            if($relativePathToActionRAWFile.StartsWith('/')){$relativePathToActionRAWFile = $relativePathToActionRAWFile.TrimStart('/','\')}

            $idiffPath = [System.IO.Path]::Join((Split-Path -Path $relativePathToActionRAWFile -Parent),([string]::Concat($VMIdentifier,'_',$using:ActionName,'.idiff')))
            $idiffPath = $idiffPath -replace ([regex]::Escape('\'),'/')

            $DockerArgs = @(
                "run"
                "--rm"
                "-v"
                ([string]::Concat($basePath,':','/images'))
                "pr3l14t0r/forensics:idifference2"
                "-x"
                $idiffPath
                ([System.IO.Path]::GetFileName($INITFileName))
                $relativePathToActionRAWFile
            )
        }

        # Invoke docker and receive the return values
        $ret = Invoke-Process -FilePath "docker" -ProcessArguments $DockerArgs
        if($ret.ExitCode -ne 0)
        {
            Write-VBox4PwshLog -Message ("The containerized idifference2.py did not finish succesfully!") -VM $VMIdentifier -Component $using:Component -Level Warning
            Write-VBox4PwshLog -Message ("STDOut: " + $ret.stdout) -VM $VMIdentifier -Component $using:Component -Level Warning -Indent 4
            Write-VBox4PwshLog -Message ("STDErr: " + $ret.stderr) -VM $VMIdentifier -Component $using:Component -Level Error -Indent 4
            break
        }
        else
        {
            # Check if there were warnings
            $warnings = $ret.stdout.Split([System.Environment]::NewLine) | Where-Object {$_ -like "*warning*"}
            if($null -ne $warnings)
            {
                Write-VBox4PwshLog -Message ("The <idifference2.py> script reported the following warnings: " + $warnings) -VM $VMIdentifier -Component $using:Component -Level Warning
            }

            # This is maybe overkill. It just saves the output from idifference2.py into the logfile.
            Write-VBox4PwshLog -Message ("The containerized idifference2.py did finish succesfully! Here's the output!") -VM $VMIdentifier -Component $using:Component -Level Verbose
            Write-VBox4PwshLog -Message ("STDOut: " + $ret.stdout) -VM $VMIdentifier -Component $using:Component -Level Verbose -Indent 4
            Write-VBox4PwshLog -Message ("STDErr: " + $ret.stderr) -VM $VMIdentifier -Component $using:Component -Level Verbose -Indent 4
        }

        # close the cloned medium in VirtualBox. This will remove the registered medium in VirtualBox and - based on the variable - also the image file
        Write-VBox4PwshLog -VM $VMIdentifier -Component $using:Component -Message ("Closing now the medium in VirtualBox...") -Level Verbose
        if($using:KeepExportedImageFile){Close-VBoxDiskMedium -Medium $RAWFileName}
        else{Close-VBoxDiskMedium -Medium $RAWFileName -Delete}
        
        Write-VBox4PwshLog -VM $VMIdentifier -Component $using:Component -Message ("All done for <"+$VMIdentifier+">. Runtime: "+([datetime]::Now - $StartTime).ToString("G")) -Level Verbose
    }
}