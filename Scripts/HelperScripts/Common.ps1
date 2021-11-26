function Start-Waiting
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Int64]
        $MinutesToWait
    )

    # Wait for X minutes
    $Seconds = ($MinutesToWait * 60)
    if($Seconds -gt 0)
    {
        Write-VBox4PwshLog -Component $Component -Message ("Waiting time: <"+$MinutesToWait+"> minutes. Continuing at: "+(([Datetime]::Now.AddSeconds($Seconds)).ToString("G")))
        Start-Sleep -Seconds $Seconds
    }
}