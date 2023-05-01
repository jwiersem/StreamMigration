
<#
.SYNOPSIS
    Script for fetching all Stream Classic videos and exporting to a CSV
.AADTENANTID
    Aad Tenant Id of the customer.
.INPUTFILE
    File Path to import the Stream token from. EX: "C:\Users\Username\Desktop\token.txt"

See https://learn.microsoft.com/en-us/stream/streamnew/migration-details#steps-to-run-the-script how to get the token

Example:
.\StreamClassicChannelMetadataGenerator.ps1 -AadTenantId "af73baa8-f594-4eb2-a39d-93e96cad61fc" -InputFile "C:\AzureDevOps\CBS New Repos\StreamOnSP\SolutionAssets\PowerShell\token.txt"

#>


[CmdletBinding()]
Param(
  [Parameter(Mandatory = $true)]
  [string]$AadTenantId = "af73baa8-f594-4eb2-a39d-93e96cad61fc",

  [Parameter(Mandatory = $true)]
  [string]$InputFile = "C:\AzureDevOps\CBS New Repos\StreamOnSP\SolutionAssets\PowerShell\token.txt"
)

Function GetBaseUrl{
    $tenantPatchUri = "https://api.microsoftstream.com/api/tenants/"+$AadTenantId+"?api-version=1.4-private"

    $body = "{}"

    #((Get-Date).tostring() + ' TenantPatch URI: ' + $tenantPatchUri + "`n") | Out-File $logFilePath -Append

    try
    {
        $response = Invoke-RestMethod -Uri $tenantPatchUri -Method Patch -Body $body -Headers $headers -ContentType "application/json"
    }
    catch
    {
        #Log error.
        #((Get-Date).tostring() + ' ' + $Error[0].ErrorDetails + "`n") | Out-File $logFilePath -Append
        #((Get-Date).tostring() + ' ' + $Error[0].Exception + "`n") | Out-File $logFilePath -Append

        #Stop execution if Unauthorized(401).
        if($_.Exception.Response.StatusCode.value__ -eq 401)
        {
            Write-Host "========Enter new token and start the script again======="
        }

        Write-Host "`nSome error occurred. Check logs for more info.`n" -ForegroundColor Red
        exit
    }

    return $response.apiEndpoint
}

$formattedDate = (Get-Date).ToString("yyyy-MM-dd-HHmmss");
$channelOutputPath = "channelMetadata_$formattedDate.csv";
$token = Get-Content -Path $InputFile;

$headers = @{
        Authorization = "Bearer $token"
    }

$apiEndPoint = GetBaseUrl;

$stepSize = 100;
$skip = 0;
$continue = $true;
$immediateStop = $false;

$allChannelData = @();

while ($continue -and !$immediateStop)
{
    Write-Host "Getting next $stepSize items starting from $skip." -ForegroundColor Green;

    $channelsEndPoint = "$($apiEndPoint)channels?api-version=1.4-private&`$top=$($stepSize)&`$skip=$($skip)&`$expand=creator,group";

    $response = Invoke-RestMethod -Uri $channelsEndPoint -Method GET -Headers $headers -ContentType "application/json";

    if (!($response) -or !($response.value))
    {
        $continue = $false;
    }
    else
    {      
        foreach($channel in $response.value)
        {
            $channelId = $channel.id;

            Write-Host "Handling channel + $channelId";

            $channelName = "";
            if ($channel.name)
            {
                $channelName = $channel.name;
            } 

            $channelDescription = "";

            if($channel.description)
            {
                $channelDescription = $channel.description;
            }

            $channelLogoURL = "";            
            if (($channel.posterImage) -and ($channel.posterImage.small) -and ($channel.posterImage.small.url))
            {
                $channelLogoURL = $channel.posterImage.small.url;
            }

            if ($channelLogoURL)
            {
                $path = ".\Images";

                If(!(test-path -PathType container $path))
                {
                      New-Item -ItemType Directory -Path $path;
                }

                $filename = ".\Images\$channelId.png";

                $imageResponse = Invoke-RestMethod -Uri $channelLogoURL -Method GET -Headers $headers -OutFile $filename;
            }

            $groupId = "";
            $groupName = "";
            $groupDescription = "";

            if ($channel.group)
            {
                $groupId = $channel.group.id;
                $groupName = $channel.group.name;
                $groupDescription = $channel.group.description;
            }

            $aChannelRow = [PSCustomObject]@{ChannelId = $channelId; ChannelName = $channelName; ChannelDescription = $channelDescription; ChannelLogoURL = $channelLogoURL; ChannelGroupId = $groupId;ChannelGroupName = $groupName; ChannelGroupDescription = $groupDescription;};

            $allChannelData += $aChannelRow;

        }

        $skip = $skip + $stepSize;
        #$immediateStop = $true;
    }

}

$allChannelData | Export-Csv -Path $channelOutputPath -Encoding UTF8 -Delimiter ';' -NoTypeInformation;

