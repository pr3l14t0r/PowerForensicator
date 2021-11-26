function New-FiwalkXML
{
<#
    .SYNOPSIS
        Creates an XML file using fiwalk.

    .DESCRIPTION
        TODO:

    .PARAMETER ImageFilePath
        Provide the location of the image file path (raw image, iso image etc.) that you want to parse!

    .PARAMETER LocalBinary
        If set, the locally installed 'fiwalk' binary will be used instead of a docker container. Make sure that 'fiwalk' is installed!
#>
[CmdletBinding()]
param (
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]
    $ImageFilePath,

    [Parameter()]
    [switch]
    $LocalBinary
)

    $Component = "New-FiwalkXML"

    # Pre-check if the path is correct
    if(-not (Test-Path -Path $ImageFilePath -PathType Leaf))
    {
        Write-VBox4PwshLog -Message ("The provided path <"+$ImageFilePath+"> does not exist! Please provide correct path!") -Component $Component -Level Error
    }

    <#
        Just in case you wonder why there is no try-catch: That is handled in the "Invoke-Process" cmldet from VBox4Pwsh module!
    #>

    if($LocalBinary)
    {

        Write-VBox4PwshLog -Message ("Creating fiwalk XML file from <"+$ImageFilePath+"> using local fiwalk binary") -Component $Component -Level Verbose
        $ret = Invoke-Process "fiwalk" -ProcessArguments ("-X",[System.IO.Path]::ChangeExtension($ImageFilePath,'xml'),$ImageFilePath)
        if($ret.ExitCode -ne 0)
        {
            Write-VBox4PwshLog -Message ("The <fiwalk> process did not finish succesfully!") -Component $Component -Level Warning
            Write-VBox4PwshLog -Message ("STDOut: " + $ret.stdout) -Component $Component -Level Warning
            Write-VBox4PwshLog -Message ("STDErr: " + $ret.stderr) -Component $Component -Level Error
            break
        }
        else
        {
            Write-VBox4PwshLog -Message ("Succefully created fiwalk-xml from image <"+$INITRawFile+">") -Component $Component -Level Verbose
        }
    }
    else
    {
        Write-VBox4PwshLog -Message ("Creating fiwalk XML file from <"+$ImageFilePath+"> using docker container") -Component $Component -Level Verbose
        # Extract the filename of the path
        $ImageFileName = [System.IO.Path]::GetFileName($ImageFilePath)

        $DockerArgs = @(
            "run"
            "--rm"
            "-v"
            ([string]::Concat([System.IO.Path]::GetDirectoryName($ImageFilePath),':','/images'))
            "--entrypoint"
            "/usr/bin/fiwalk"
            "pr3l14t0r/forensics:idifference2"
            "-X"
            [System.IO.Path]::ChangeExtension($ImageFileName,'xml')
            $ImageFileName
        )

        $ret = Invoke-Process -FilePath "docker" -ProcessArguments $DockerArgs

        if($ret.ExitCode -ne 0)
        {
            Write-VBox4PwshLog -Message ("The containerized idifference2.py did not finish succesfully!") -Component $Component -Level Warning
            Write-VBox4PwshLog -Message ("STDOut: " + $ret.stdout) -Component $Component -Level Warning
            Write-VBox4PwshLog -Message ("STDErr: " + $ret.stderr) -Component $Component -Level Error
            break
        }
    }

    Write-VBox4PwshLog -Message ("Successfully created fiwalk XML at path <"+([System.IO.Path]::ChangeExtension($ImageFilePath,"xml"))+">!") -Component $Component -Level Verbose
}