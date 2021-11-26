function Get-FSMountCharacteristicEvidences
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

        #ToDo: Add explanation
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $OutFileName = [System.IO.Path]::Combine($ImageDirectory,([System.String]::Concat($VM,"-",$ActionName,"-FSMounts-","CharacteristicEvidence.txt"))),

        # Counter for the minimum amount of occurences for an evidence to be characteristic. Default will be the amount of imported Action evidence files.
        [Parameter()]
        [AllowNull()]
        # nullable int is needed cause [int] get's automatically initialized to zero 
        [nullable[int]]
        $MinCount
    )

$Component = "Get-FSMountCharacteristicEvidences"
Write-VBox4PwshLog -Message ("Fetching the NOISE FileSystemMount evidence file(s)") -VM $VM -Component $Component -Level Verbose
$NoiseEvidencePaths = Get-ChildItem -Path ([System.IO.Path]::Combine($ImageDirectory,"Noise")) -Recurse -Force -Filter ("*"+$VM+"*Noise*FileSystemMounts*Difference*")
if($null -eq $NoiseEvidencePaths)
{
    Write-VBox4PwshLog -Message ("No files found! That does usually mean, that there are no differences in FileSystemMounts between INIT and NOISE!") -VM $VM -Component $Component -Level Verbose
}
else
{
    Write-VBox4PwshLog -Message ("Feteched <"+$NoiseEvidencePaths.Count+"> file(s):"+[System.Environment]::NewLine+($NoiseEvidencePaths.FullName -join ([System.Environment]::NewLine))) -VM $VM -Component $Component -Level Verbose
}

Write-VBox4PwshLog -Message ("Fetching the <"+$ActionName+"> action evidence file(s)") -VM $VM -Component $Component -Level Verbose
$ActionEvidencePaths = Get-ChildItem -Path ([System.IO.Path]::Combine($ImageDirectory,$ActionName)) -Recurse -Force -Filter ("*"+$VM+"*"+$ActionName+"*FileSystemMounts*Difference*")
if($null -eq $ActionEvidencePaths)
{
    Write-VBox4PwshLog -Message ("No files found! That does usually mean, that there are no differences in FileSystemMounts between ACTION and NOISE!") -VM $VM -Component $Component -Level Verbose
}
else
{
    Write-VBox4PwshLog -Message ("Feteched <"+$ActionEvidencePaths.Count+"> file(s):"+[System.Environment]::NewLine+($ActionEvidencePaths.FullName -join ([System.Environment]::NewLine))) -VM $VM -Component $Component -Level Verbose   
}

#Importing the text now
Write-VBox4PwshLog -Message ("Importing files now (if any) and substracting NOISE from ACTION") -VM $VM -Component $Component -Level Verbose

#only import noise if not empty
if($null -ne $NoiseEvidencePaths)
{
    $NoiseEvidenceContent = $NoiseEvidencePaths.FullName | ForEach-Object {[System.IO.File]::ReadAllLines($_)} | Sort-Object
    Write-VBox4PwshLog -Message ("Unfiltered <noise> evidence count: "+$NoiseEvidenceContent.Count) -VM $VM -Component $Component -Level Verbose

    # filter now. A line has to be in every instance of a file to be characteristic.
    # That means: if we have 10 evidence files, the example line "/tmp/myfile   mcacr" needs to occur exact 10 times to be characteristic. 
    Write-VBox4PwshLog -Message ("Filtering <noise> evidences now") -VM $VM -Component $Component -Level Verbose
    if($null -ne $MinCount)
    {
        Write-VBox4PwshLog -Message ("Param 'MinCount' has been specified and set to: <"+$MinCount+">") -VM $VM -Component $Component -Level Verbose
        $characteristicNoiseContent = $NoiseEvidenceContent | Group-Object | Where-Object {$_.Count -ge $MinCount} | Select-Object Name,Count
    }
    else
    {
        Write-VBox4PwshLog -Message ("Param 'MinCount' has NOT been specified, using the amount of evidences file for <noise> as counter: <"+$NoiseEvidencePaths.Count+">") -VM $VM -Component $Component -Level Verbose
        $characteristicNoiseContent = $NoiseEvidenceContent | Group-Object | Where-Object {$_.Count -ge $NoiseEvidencePaths.Count} | Select-Object Name,Count
    }
}
else
{
    Write-VBox4PwshLog -Message ("No Noise evidence content imported as there are none!") -VM $VM -Component $Component -Level Verbose
    $NoiseEvidenceContent = $null
}

if($null -eq $characteristicNoiseContent)
{
    Write-VBox4PwshLog -Message ("There are no characteristc evidence for 'NOISE'. You may try to lower the 'MinCount' parameter!") -VM $VM -Component $Component -Level Verbose
    $characteristicNoiseContent = $null
}

if($null -ne $ActionEvidencePaths)
{
    $ActionEvidenceContent = $ActionEvidencePaths.FullName | ForEach-Object {[System.IO.File]::ReadAllLines($_)} | Sort-Object
    Write-VBox4PwshLog -Message ("Unfiltered <action> evidence count: "+$ActionEvidenceContent.Count) -VM $VM -Component $Component -Level Verbose

    # filter now. A line has to be in every instance of a file to be characteristic.
    # That means: if we have 10 evidence files, the example line "/tmp/myfile   mcacr" needs to occur exact 10 times to be characteristic.
    Write-VBox4PwshLog -Message ("Filtering <action> evidences now") -VM $VM -Component $Component -Level Verbose
    if($null -ne $MinCount)
    {
        Write-VBox4PwshLog -Message ("Param 'MinCount' has been specified and set to: <"+$MinCount+">") -VM $VM -Component $Component -Level Verbose
        $characteristicActionContent = $ActionEvidenceContent | Group-Object | Where-Object {$_.Count -ge $MinCount} | Select-Object Name,Count
    }
    else
    {
        Write-VBox4PwshLog -Message ("Param 'MinCount' has NOT been specified, using the amount of evidences file for <action> as counter: <"+$ActionEvidencePaths.Count+">") -VM $VM -Component $Component -Level Verbose
        $characteristicActionContent = $ActionEvidenceContent | Group-Object | Where-Object {$_.Count -ge $ActionEvidencePaths.Count} | Select-Object Name,Count
    }
    if($null -eq $characteristicActionContent)
    {
        Write-VBox4PwshLog -Message ("There are no characteristc evidence for 'ACTION'. You may try to lower the 'MinCount' parameter!") -VM $VM -Component $Component -Level Verbose
        # Creating an empty array because of laziness
        # using this way, i do not have to make the 'foreach($line in $characteristicActionContent)' more complex than necessary!
        #    '.contains()' will deliver a $false instead of an error
        [string[]]$characteristicActionContent = @()
    }
    
    $CharacteristicEvidences = @()
    
    # Filter out now the lines that occur both in ActionEvidences and NoiseEvidences
    # For the sake of readability, this one is an unecessary big foreach loop

    foreach($line in $characteristicActionContent)
    {
        # Only check content of $characteristicNoiseContent if there is any!
        if(($null -ne $characteristicNoiseContent) -and ($characteristicNoiseContent.Name.Contains($line.Name)))
        {
            # the line is in noise as well. Not characteristic, thus fallthrough
            Write-VBox4PwshLog -Message ("NOT chacteristic: "+$line.Name) -VM $VM -Component $Component -Level Verbose
        }
        else
        {
            # line is not contained within the noise evidences. Therefore it will be considered as characteristic.
            #Write-VBox4PwshLog -Message ("Chacteristic: "+$line) -VM $VM -Component $Component -Level Verbose
            $CharacteristicEvidences += [string]::Concat($line.Name," ",$line.Count)
        }
    }

    # output
    Write-VBox4PwshLog -Message ("Done!") -VM $VM -Component $Component -Level Verbose
    Write-VBox4PwshLog -Message ("Found <"+$CharacteristicEvidences.Count+"> chracteristic FileSystemMount evidences for action <"+$ActionName+"> on vm <"+$VM+">!") -VM $VM -Component $Component

    if($CharacteristicEvidences.Count -gt 0)
    {
        Write-VBox4PwshLog -Message ("Exporting them now to <"+$OutFileName+">") -VM $VM -Component $Component
        $CharacteristicEvidences | Set-Content -Path $OutFileName -Force
    }
    else 
    {
        # Write-VBox4PwshLog -Message ("Nothing to export!") -VM $VM -Component $Component
    }   
}
else
{
    # As there are no action evidence paths, fall through!
    Write-VBox4PwshLog -Message ("There are no FileSystemMount specific action evidence for <"+$VM+">. Nothing to export!") -VM $VM -Component $Component
}

# return the filename. Maybe unecessary!
# return $OutFileName
}