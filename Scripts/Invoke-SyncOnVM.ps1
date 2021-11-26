function Invoke-SyncOnVM
{
<#
    .SYNOPSIS
        Runs "sync" on a VM.

    .DESCRIPTION
        "Sync" causes all pending modifications to filesystem metadata and cached file data to be written to the underlying filesystems.
        Explanation taken from: https://man7.org/linux/man-pages/man2/sync.2.html
        This commandlets differetiates between Windows, Linux and MAC. On Windows please make sure that you can run "sync.exe" (from Sysinternals) through PATH

    .Parameter EnvironmentVariables
        Sets, modifies, and unsets environment variables in the environment in which the program will run. Optional.
        Provide a hashlist consting out of key-value pairs

    .Parameter UserName
        Provide the UserName of the user in whichs context the program shall run. Optional.

    .Parameter Password
        Provide the password of a user. Optional. 
#>
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $VM,

        [Parameter()]
        [string] $UserName,
    
        [Parameter()]
        [string] $Password,

        [Parameter()]
        [AllowNull()]
        [Hashtable] $EnvironmentVariables
    )

    $Component = "Invoke-SyncOnVM"

    # Get information about guest OS first
    $VBoxInfo = Get-VBoxVMInformation -VMIdentifier $VM

    # now try to invoke "sync" based on the virtual machines OS
    Write-VBox4PwshLog -Message ("Trying to execute 'sync' now on VM <"+$VM+">. Fetching OS Information first...") -VM $VM -Component $Component -Level Verbose

    if($VBoxInfo.GuestOSType -like "*Linux*")
    {
        $ret = Invoke-VboxVMProcess -FilePath "/bin/sync" -Params ("sync") -VMIdentifier $VM -WaitSTDOut -WaitSTDErr -EnvironmentVariables $EnvironmentVariables -UserName $UserName -Password $Password -PassThru
    }
    elseif($VBoxInfo.GuestOSType -like "*windows*")
    {
        Write-VBox4PwshLog -Message ("Executing 'sync' on a Windows VM is currently not implemented, but on the roadmap!!!") -VM $VM -Component $Component -Level Warning
    }
    else
    {
        Write-VBox4PwshLog -Message ("Detected an unsupported guest OS type: <"+$VBoxInfo.GuestOSType+">") -VM $VM -Component $Component -Level Warning
    }

    if($ret.ExitCode -eq 0)
    {
        Write-VBox4PwshLog -Message ("Sucesfully ran 'sync' on vm <"+$VM+">!") -VM $VM -Component $Component -Level Verbose
    }
    else
    {
        Write-VBox4PwshLog -Message ("Executing 'sync' on vm <"+$VM+"> has not been succesfull!") -VM $VM -Component $Component -Level Error
    }
}