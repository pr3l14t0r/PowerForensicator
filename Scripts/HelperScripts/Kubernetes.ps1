function Get-FSMounts
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $VM,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $VMUserName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $VMUserPassword,

        [Parameter()]
        [system.collections.hashtable]
        $StringsToReplace,

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $OutFileName
    )

$Component = "Get-FSMounts"

# We need a little recursive function that calls itself whenever an object contains child-nodes
function Optimize-FSMountPoints($MountEntry)
{
    # this function throws a custom object whenever a mount does not contain children. 
    # If it does contain children, the function will iterate through those recursevily
    if($null -ne $MountEntry.children)
    {
        foreach ($entry in $MountEntry.children) {
            Optimize-FSMountPoints -MountEntry $entry
        }
    }

    [PSCustomObject]@{
        "Target" = $MountEntry.target
        "Source" = $MountEntry.source
        "FSType" = $MountEntry.fstype
        "Options" = $MountEntry.options
    }
}

Write-VBox4PwshLog -Message ("Receiving the mount points now from VM <"+$VM+">") -VM $VM -Component $Component -Level Verbose
$ret = Invoke-VboxVMProcess -VMIdentifier $VM -FilePath "/bin/findmnt" -Params ("findmnt","--json") -UserName $VMUserName -Password $VMUserPassword -WaitSTDOut -WaitSTDErr -PassThru

# In case the $StringsToReplace var is set, some lines are going to get changed!
if($null -ne $StringsToReplace)
{
    Write-VBox4PwshLog -Message ("Strings to replace have been set. This will be done now.") -VM $VM -Component $Component -Level Verbose
    foreach($key in $StringsToReplace.Keys)
    {
        $ret.stdout = $ret.stdout -replace ([regex]::Escape($key),$StringsToReplace[$key])
    }
}

$mounts = @()

foreach ($fs in ($ret.stdout | ConvertFrom-Json).filesystems) {
    $mounts += Optimize-FSMountPoints -MountEntry $fs
}

if(-not [string]::IsNullOrEmpty($OutFileName))
{
    Write-VBox4PwshLog -Message ("An output-file has been specified! The received mount-points will be exported to <"+$OutFileName+">!") -VM $VM -Component $Component -Level Verbose
    $mounts | Sort-Object -Property Target | Out-File -FilePath $OutFileName -Width 4096 -Force
}

# finally return the mountpoints-object
return $mounts
}

function Compare-FSMounts
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [PSCustomObject]
        $ReferenceFSMount,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [PSCustomObject]
        $DifferenceFSMount
    )

$Component = "Compare-FSMounts"

<# JUST FOR DEVELOPING PURPOSES!
# imaginary fsmount that has been added
$DifferenceFSMount += [pscustomobject]@{"Target" = "/var/lib/kubelet/IHaveBeenAdded";"Source"="tmpfs";"FSType"="tmpfs";"Options"="rw,nosuid,nodev,noexec,relatime,rdma"}

# imaginary fsmount that has been deleted
$ReferenceFSMount += [pscustomobject]@{"Target" = "/var/lib/kubelet/IThinkIGotLost!";"Source"="tmpfs";"FSType"="tmpfs";"Options"="rw,nosuid,nodev,noexec,relatime,rdma"}

# now add something to both ref and diff, where the "Options" did change
$ReferenceFSMount += [pscustomobject]@{"Target" = "/var/wtf/foo/MyMountOptionsWhereChanged";"Source"="tmpfs";"FSType"="tmpfs";"Options"="rw,nosuid,nodev,noexec,relatime,rdma"}
$DifferenceFSMount += [pscustomobject]@{"Target" = "/var/wtf/foo/MyMountOptionsWhereChanged";"Source"="tmpfs";"FSType"="tmpfs";"Options"="rw,notAnOption,LFMAO"}

# now add something to both ref and diff, where the "Source" did change
$ReferenceFSMount += [pscustomobject]@{"Target" = "/var/wtf/foo/MySourceWillChange";"Source"="tmpfs";"FSType"="tmpfs";"Options"="rw,nosuid,nodev,noexec,relatime,rdma"}
$DifferenceFSMount += [pscustomobject]@{"Target" = "/var/wtf/foo/MySourceWillChange";"Source"="NTFS";"FSType"="tmpfs";"Options"="rw,nosuid,nodev,noexec,relatime,rdma"}

# now add something to both ref and diff, where the "FSType" did change
$ReferenceFSMount += [pscustomobject]@{"Target" = "/var/wtf/foo/MyFSTypeWillChange";"Source"="tmpfs";"FSType"="tmpfs";"Options"="rw,nosuid,nodev,noexec,relatime,rdma"}
$DifferenceFSMount += [pscustomobject]@{"Target" = "/var/wtf/foo/MyFSTypeWillChange";"Source"="tmpfs";"FSType"="NTFS";"Options"="rw,nosuid,nodev,noexec,relatime,rdma"}

# now add something to both ref and diff, where the "FSType" and "OPTION" did change
$ReferenceFSMount += [pscustomobject]@{"Target" = "/var/wtf/foo/MyFSTypeAndOptionWillChange";"Source"="tmpfs";"FSType"="tmpfs";"Options"="rw,nosuid,nodev,noexec,relatime,rdma"}
$DifferenceFSMount += [pscustomobject]@{"Target" = "/var/wtf/foo/MyFSTypeAndOptionWillChange";"Source"="tmpfs";"FSType"="NTFS";"Options"="rw,notAnOption,LFMAO"}

#>

[string[]]$out=@()


# Parse only the mount "Targets" first to see, which ones got added and/or removed.
$result = Compare-Object -ReferenceObject $ReferenceFSMount -DifferenceObject $DifferenceFSMount -Property Target

foreach($res in $result)
{
    <# translate the SiteIndicator 
        '=>' means that something is included within the DifferenceObject, which is not part of the ReferenceObject
        so: '=>' == ADDED

        '<=' means that something IS NOT included within the DifferenceObject, but has been part of the ReferenceObject
        so: '<=' == REMOVED
    #>
    if($res.SideIndicator -eq '=>'){$indicator = 'ADDED'}
    elseif($res.SideIndicator -eq '<='){$indicator = 'REMOVED'}
    else
    {
        Write-VBox4PwshLog -Message ("Unknown side indicator: <"+$res.SideIndicator+">") -Component $Component -Level Warning
        $indicator = $res.SideIndicator
    }

    $out += [string]::Concat($res.Target," ",$indicator)
}

# Now, parse all Objects that have the same "Target" Name and see if other properties did change!
$NonDifferentTargetNames = Compare-Object -ReferenceObject $ReferenceFSMount -DifferenceObject $DifferenceFSMount -Property Target -ExcludeDifferent -PassThru | Select-Object -ExpandProperty Target -Unique

foreach($target in $NonDifferentTargetNames)
{
    $changedProperties = @()

    $refMount = $ReferenceFSMount | where {$_.Target -eq $target}
    $diffMount = $DifferenceFSMount | where {$_.Target -eq $target}

    # Check "Source"
    if(Compare-Object -ReferenceObject $refMount -DifferenceObject $diffMount -Property Source){$changedProperties += "Source_CHANGED"}
    # Check "FSType"
    if(Compare-Object -ReferenceObject $refMount -DifferenceObject $diffMount -Property FSType){$changedProperties += "FSType_CHANGED"}
    # Check "Options"
    if(Compare-Object -ReferenceObject $refMount -DifferenceObject $diffMount -Property Options){$changedProperties += "Options_CHANGED"}

    if($changedProperties)
    {
        $out += [string]::Concat($target," ",($changedProperties -join ","))
    }
}

return $out

}

function Find-StringsToReplaceInPods
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [PSCustomObject]
        $Pods
    )

    $StringsToReplace = New-Object System.Collections.Hashtable

    $PODCounter=1
    foreach($pod in $Pods)
    {
        $StringsToReplace.Add($pod.metadata.uid,[System.String]::Concat('$PodID$',$pod.metadata.name,'$'))
    
        $ContainerCounter=1
        foreach($container in $pod.spec.containers)
        {
            #try to match the containerStatus object by best effort
            $containerStatus = $pod.status.containerStatuses | Where-Object {($_.name -eq $container.name) -and ($_.image -match [regex]::Escape($container.image))}
            
            # Add the container ID to replace it with 
            $StringsToReplace.Add($containerStatus.containerID.Replace([regex]::Escape('containerd://'),''),[System.String]::Concat('$ContID$',$containerStatus.name,'$'))
    
            $containerVolumeMountCounter = 1
            foreach($containerVolumeMount in $container.volumeMounts)
            {
                # replace the name of the volume mount here!
                $StringsToReplace.Add($containerVolumeMount.name,[System.String]::Concat('$ContID$VolumeMount$',$containerStatus.name,'$',$containerVolumeMountCounter,'$'))
                $containerVolumeMountCounter++
            }
    
            $ContainerCounter++
        }
        $PODCounter++
    }

    return $StringsToReplace
}

function Wait-PodDeployment
{
    [CmdletBinding()]
    param (
        [Parameter(ParameterSetName="ByParameter")]
        [string]
        $PodName,

        [Parameter(ParameterSetName="ByParameter")]
        [string]
        $NameSpace,

        [Parameter(ParameterSetName="ByFile")]
        [string]
        $File
    )

    $Component = "Wait-PodDeployment"

    if($PSCmdlet.ParameterSetName -eq "ByParameter")
    {

        [string[]]$kubectlArgs = @()
        if($NameSpace){$kubectlArgs += [string[]]("--namespace",$NameSpace)}

        if($PodName){$kubectlArgs += [string[]]("get","pod",$PodName)}
        else{$kubectlArgs += [string[]]("get","pods")}

        # add json output
        $kubectlArgs += [string[]]("-o","json")
    }
    elseif($PSCmdlet.ParameterSetName -eq "ByFile")
    {
        $kubectlArgs = [string[]]("get","-f",$File,"-o","JSON")
    }

    Write-VBox4PwshLog -Component $Component -Message ("Waiting now for the changes to be applied") -Level Verbose
    $DeploymentFinished = $false

    $totalSeconds = 0
    do
    {
        Start-Sleep -Seconds 15
        $totalSeconds += 15
        if($totalSeconds -gt 300)
        {
            Write-VBox4PwshLog -Component $Component -Message ("The waiting for deployment to be finished now exceeded the threshold of 5 Minutes and runs since <"+$totalSeconds+"> seconds!") -Level Warning
            Write-VBox4PwshLog -Component $Component -Message ("Please verify the cluster/ deployment state manually using 'kubectl'!") -Level Warning
        }
        # This line gets the current status
        $Pods = @(Invoke-Kubectl -kubectlArgs $kubectlArgs | ConvertFrom-Json)

        if($Pods.items){$Pods = $Pods.items}

        # I need to check either the "phase" of the pod(s) or the state of the container(s)
        foreach($pod in $Pods)
        {
            Write-VBox4PwshLog -Component $Component -Message ("The pod <"+$pod.metadata.name+"> is in state <"+$pod.status.phase+">!") -Level Verbose
            if($pod.status.phase -in @("Succeeded","Running")){$DeploymentFinished = $true}
            else 
            {
                if($totalSeconds -gt 300)
                {
                    Write-VBox4PwshLog -Component $Component -Message ("The pod <"+$pod.metadata.name+"> is still in state <"+$pod.status.phase+">!") -Level Warning
                }
                $DeploymentFinished = $false
                break
            }
        }
    }
    while(-not $DeploymentFinished)

    return $Pods
}

function Invoke-Kubectl
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [string[]]
        $kubectlArgs,

        [Parameter()]
        [Int64]
        $RetryCount = 10
    )

    $Component = "Invoke-Kubectl"

    Write-VBox4PwshLog -Message ("Running kubectl...") -Component $Component -Level Verbose

    $tries = 1
    do
    {

        $ret = Invoke-Process -FilePath 'kubectl' -ProcessArguments $kubectlArgs

        if($ret.ExitCode -ne 0)
        {
            Write-VBox4PwshLog -Message ("Not Succesful. Received from STDErr: "+$ret.stderr) -Component $Component -Level Verbose
            Write-VBox4PwshLog -Message ("Retries left: <"+($RetryCount - $tries)+">") -Component $Component -Level Verbose
            Start-Sleep -Seconds 5
            $tries++
        }
    }
    while(($ret.ExitCode -ne 0) -and ($tries -le $RetryCount))

    if($ret.ExitCode -ne 0)
    {
        Write-VBox4PwshLog -Message ("An error occured while running kubectl and RetryCount of <"+$RetryCount+"> has been exceeded!") -Component $Component -Level Warning
        Write-VBox4PwshLog -Message ("returned by STDOut: "+$ret.stdout) -Component $Component -Level Warning
        Write-VBox4PwshLog -Message ("returned by STDErr: "+$ret.stderr) -Component $Component -Level Error
        throw $ret.stderr
        break
    }
    else
    {
        Write-VBox4PwshLog -Message ("kubectl returned the following: `n"+($ret.stdout)) -Component $Component -Level Verbose

        return $ret.stdout
    }
}

function Test-Kubectl
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [AllowEmptyString()]
        [string]
        $KubeConfig,

        [Parameter()]
        [string]
        $VM,

        [Parameter()]
        [string]
        $VMUserName,

        [Parameter()]
        [string]
        $VMUserPassword
    )

$Component = "Test-Kubectl"

Write-VBox4PwshLog -Message ("Checking kubeconfig and testing kubectl...") -Component $Component

# Download kubeconfig from master if necessary
if([string]::IsNullOrEmpty($KubeConfig))
{
    Write-VBox4PwshLog -Message ("No 'KubeConfig' file has been specified. Checking if the environment variable 'KUBECONFIG' has been set...") -Component $Component -Level Verbose
    if([string]::IsNullOrEmpty($Env:KUBECONFIG))
    {
        # The path resolves to:
        # Linux: /tmp
        # Windows: C:\Users\$USER$\AppData\Local\Temp\
        $tmpPath = [System.IO.Path]::GetTempPath()
        Write-VBox4PwshLog -Message ('Both the local "$Kubeconfig" and/or environment variable "KUBECONFIG" are not set. Fetching the kubeconfig file now from the Kubernetes Master Server.') -Component $Component -Level Warning
        Write-VBox4PwshLog -Message ("Fetching it now and saving it in <"+$tmpPath+">.") -Component $Component

        if(-not [string]::IsNullOrEmpty($VMUserName)){$KubeConfigPathOnVM = [string]::Concat('/home/',$VMUserName,'/.kube/config')}
        else{$KubeConfigPathOnVM = '~/.kube/config'}

        $KubeConfig = [System.IO.Path]::Combine($tmpPath,'config')

        # if already exists, delete it!
        if(Test-Path -Path $KubeConfig -PathType Leaf){$null = Remove-Item -Path $KubeConfig -Force}

        Copy-FileFromVBoxVM -VMIdentifier $VM -Source $KubeConfigPathOnVM -Destination $tmpPath -UserName $VMUserName -Password $VMUserPassword

        # verfiy the file 
        if(-not (Test-Path -Path $KubeConfig -PathType Leaf))
        {
            # stop
            Write-VBox4PwshLog -Message ("The specified path <"+$KubeConfig+"> does not exist!") -Component $Component -Level Error
            break
        }
        else
        {
            Write-VBox4PwshLog -Message ("Verified that path <"+$KubeConfig+"> does exist!") -Component $Component -Level Verbose
            Write-VBox4PwshLog -Message ("Setting the file now as environment variable for kubectl.") -Component $Component -Level Verbose
            $Env:KUBECONFIG = $KubeConfig
        }
    }
    else
    {
        Write-VBox4PwshLog -Message ("The environment variable 'KUBECONFIG' does exist and has been set! Value: <"+$Env:KUBECONFIG+">") -Component $Component -Level Verbose
    }
}
else
{
        # verfiy the file 
        if(-not (Test-Path -Path $KubeConfig -PathType Leaf))
        {
            # stop
            Write-VBox4PwshLog -Message ("The specified path <"+$KubeConfig+"> does not exist!") -Component $Component -Level Error
            break
        }
        else
        {
            Write-VBox4PwshLog -Message ("Verified that path <"+$KubeConfig+"> does exist!") -Component $Component -Level Verbose
            Write-VBox4PwshLog -Message ("Setting the file now as environment variable for kubectl.") -Component $Component -Level Verbose
            $Env:KUBECONFIG = $KubeConfig
        }
}
Write-VBox4PwshLog -Message ("Using kubeconfig: <"+$Env:KUBECONFIG+">!") -Component $Component

Write-VBox4PwshLog -Message ("Performing a test run of 'kubectl get nodes' now...") -Component $Component

# check now whether 'kubectl get nodes' will run.
$ret = Invoke-Process -FilePath 'kubectl' -ProcessArguments ("get","nodes")
if($ret.ExitCode -eq 0)
{
    Write-VBox4PwshLog -Message ("Test-Run of kubectl did finish succesfully! All set!") -Component $Component -Verbose
}
else
{
    Write-VBox4PwshLog -Message ("An error occured during the test-run of 'kubectl'!") -Component $Component -Level Warning
    Write-VBox4PwshLog -Message ("returned by STDOut: "+$ret.stdout) -Component $Component -Level Warning
    Write-VBox4PwshLog -Message ("returned by STDErr: "+$ret.stderr) -Component $Component -Level Error
    throw $ret.stderr
    break
}
}