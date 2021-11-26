function Format-ActionEvidence
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
        $ActionName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({Test-Path -Path $_ -PathType Container})]
        [string]
        $ImageDirectory, #ToDo: Add explanation

        [Parameter()]
        [system.collections.hashtable]
        $StringsToReplace,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $OutFileName = [System.IO.Path]::Combine($ImageDirectory,([System.String]::Concat($VM,"-",$ActionName,"-","Evidence.txt"))) #ToDo: Add explanation - 'The name of the file you want: myname.txt'
    )

function Format-ChangedTimeStamps($fileobject)
{
    $timestamps =""
    if($fileobject.mtime.changed_property -eq "1"){$timestamps+='m'}
    if($fileobject.ctime.changed_property -eq "1"){$timestamps+='c'}
    if($fileobject.atime.changed_property -eq "1"){$timestamps+='a'}
    if($fileobject.crtime.changed_property -eq "1"){$timestamps+='cr'}

    return $timestamps
}

$Component = "Format-ActionEvidence"

# Step 1: Receive all idiff files for the action of a specific VM
Write-VBox4PwshLog -Message ("Looking for *.idiff file and loading it accordingly") -VM $VM -Component $Component -Level Verbose
$iDiffFile = Get-ChildItem -Path $ImageDirectory -Recurse -Force -Filter ("*"+ $VM + "*" + $ActionName + "*.idiff")
Write-VBox4PwshLog -Message ("Found the following file:`n"+$iDiffFile.FullName) -VM $VM -Component $Component -Level Verbose

if($iDiffFile.Count -gt 1)
{
    Write-VBox4PwshLog -Message ("More than one *.idiff file has been detected! Please verify that! Only one should be loaded within this function.") -VM $VM -Component $Component -Level Warning
}

# All good, step 3: parse the files!
Write-VBox4PwshLog -Message ("Parsing the iDiff file now...") -VM $VM -Component $Component -Level Verbose

$PreContent = @()

[xml]$idiff = [xml]([System.IO.File]::ReadAllText($iDiffFile))

foreach($fileObject in @(($idiff.dfxml.volume.fileobject | Where-Object {$_ -ne $null})))
{
    $ChangedProperties = ""

    #if($fileObject.OuterXml -match [regex]::Escape('renamed_file="1"'))
    if($fileObject.renamed_file -or $fileobject.filename.changed_property)
    {
        # This file got renamed
        # Timestamp for this will be translated to 'r'
        $ChangedProperties += "r"
    }
    #if($fileObject.OuterXml -match [regex]::Escape('new_file="1"'))
    if($fileObject.new_file)
    {
        # This is a new file. 
        # Timestamp for this will be translated to 'cr'
        $ChangedProperties += "cr"
    }
    #if($fileObject.OuterXml -match [regex]::Escape('deleted_file="1"'))
    if($fileObject.deleted_file)
    {
        # file has been deleted
        # Timestamp for this will be translated to 'd'
        $ChangedProperties += "d"
    }
    #if($fileObject.OuterXml -match [regex]::Escape('changed_file="1"'))
    if($fileObject.changed_file -or $fileobject.modified_file)
    {
        # file has been changed/modified. This means, that either the content and/or the files timestamps changed.
        # we need to find out, which timestamps have changed. Those will be added to the counter
        $ChangedProperties += (Format-ChangedTimeStamps -fileobject $fileObject)
    }

    if(-not [string]::IsNullOrEmpty($ChangedProperties))
    {
        # In case that this a deleted file, the filename is only accesible via '.original_fileobject.filename'
        if($fileObject.deleted_file){$PreContent += [string]::Concat($fileObject.original_fileobject.filename," ",$ChangedProperties)}
        elseif($fileObject.filename.changed_property){$PreContent += [string]::Concat($fileObject.filename.'#text'," ",$ChangedProperties)}
        else{$PreContent += [string]::Concat($fileObject.filename," ",$ChangedProperties)}
    }
}

# In case the $StringsToReplace var is set, some lines are going to get changed!
if($null -ne $StringsToReplace)
{
    Write-VBox4PwshLog -Message ("Strings to replace have been set. This will be done now.") -VM $VM -Component $Component -Level Verbose
    for ($i = 0; $i -lt $PreContent.Count; $i++) {
        foreach($key in $StringsToReplace.Keys)
        {
           $PreContent[$i] = $PreContent[$i] -replace ([regex]::Escape($key),$StringsToReplace[$key])
        }
    }
}

# Output the content finally!
$PreContent | Set-Content -Path $OutFileName

Write-VBox4PwshLog -Message ("Done! Wrote the evidences file to: "+$OutFileName) -VM $VM -Component $Component
}