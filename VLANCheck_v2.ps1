##########################################
#  JSON Handlers for large JSON outputs  #
#  Section only needs for PoSH 4.0       #
##########################################

[void][System.Reflection.Assembly]::LoadWithPartialName("System.Web.Extensions")
$javaScriptSerializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$javaScriptSerializer.MaxJsonLength = [System.Int32]::MaxValue
$javaScriptSerializer.RecursionLimit = 99

function ParseItem($jsonItem) 
{
if($jsonItem.PSObject.TypeNames -match 'Array') 
    {
return ParseJsonArray($jsonItem)
    }
elseif($jsonItem.PSObject.TypeNames -match 'Dictionary') 
    {
return ParseJsonObject([HashTable]$jsonItem)
    }
else 
    {
return $jsonItem
    }
}
function ParseJsonObject($jsonObj) 
{
$result = New-Object -TypeName PSCustomObject
foreach ($key in $jsonObj.Keys) 
    {
$item = $jsonObj[$key]
if ($item) 
        {
$parsedItem = ParseItem $item
        }
else 
        {
$parsedItem = $null
        }
$result | Add-Member -MemberType NoteProperty -Name $key -Value $parsedItem
    }
return $result
}
function ParseJsonArray($jsonArray) 
{
$result = @()
$jsonArray | ForEach-Object -Process {
$result += , (ParseItem $_)
    }
return $result
}
function ParseJsonString($json) 
{
$config = $javaScriptSerializer.DeserializeObject($json)
return ParseJsonObject($config)
}

# Our custom function for dynamically checking for exact UCSD workflow input names and generating the URI for executing the workflow through a northbound API

function Get-UCSDURIs
{
    [CmdletBinding()][OutputType('System.Collections.Generic.List[System.Object]')]

    param(
    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$NexusList,

    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$UCSDGroup,

    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$VLANName,

    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$VLANID,

    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$NexusModel,

    [parameter(Mandatory=$true)]
    [ValidateNotNullorEmpty()]
    [string]$UCSDWorkflow,

    [parameter(Mandatory=$true)]
    [ValidateNotNullorEmpty()]
    [string]$UCSDSRID

    )

    $workflow_input_ht = @{}
    $workflow_input_uri = "https://your.ucsd.url.com/app/api/rest?formatType=json&opName=userAPIGetWorkflowInputs&opData={param0:`"$($UCSDWorkflow)`"}"
    $workflow_input_response = Connect-NestedPSSession -PSAServer $ucsd_psa_server -PSAUser $ucsd_psa_user -PSAPassword $ucsd_psa_pass -URI $workflow_input_uri -Headers $headers -Method Get
    $workflow_input_response = ParseJsonString($workflow_input_response.Content)

    foreach($stuff in $workflow_input_response.serviceResult.details)   {  $workflow_input_ht.Add("$($stuff.label)", $stuff.name)  }

    $sr_uris = New-Object System.Collections.Generic.List[System.Object]
    $total_list_array = $NexusList.Split(",")
    
    foreach($nexus_device in $total_list_array)
    {
        $workflow_uri_start = "https://your.ucsd.url.com/app/api/rest?formatType=json&opName=userAPISubmitWorkflowServiceRequest&opData={param0:`"$($UCSDWorkflow)`",param1:{`"list`":["
        $full_API_string = ""
        foreach($APIVar in ($workflow_input_ht.GetEnumerator() | Sort-Object -Property Value))
        {
            if($APIVar.Value -Match "switch")  {  $API_string = "{`"name`":`"$($APIVar.Value)`",`"value`":`"`"},"  }
            elseif($APIVar.Value -Match "UCSD_Group")  {   $API_string = "{`"name`":`"$($APIVar.Value)`",`"value`":`"$($UCSDGroup)`"},"  }
            elseif($APIVar.Value -Match "VLAN_Name")   { $API_string = "{`"name`":`"$($APIVar.Value)`",`"value`":`"$($VLANName)`"},"  }
            elseif($APIVar.Value -Match "VLAN_ID")  { $API_string = "{`"name`":`"$($APIVar.Value)`",`"value`":`"$($VLANID)`"}," } 
            elseif($APIVar.Value -Match "Nexus_List")  { $API_string = "{`"name`":`"$($APIVar.Value)`",`"value`":`"$($nexus_device)`"},"  }  
            elseif($APIVar.Value -Match "Model")  { $API_string = "{`"name`":`"$($APIVar.Value)`",`"value`":`"$($NexusModel)`"}," }
            elseif($APIVar.Value -Match "ps_agent") { $API_string = "{`"name`":`"$($APIVar.Value)`",`"value`":`"$($ucsd_psa_server)`"}," }
            $full_API_string += $API_String
        }    
        $full_API_string = $full_API_string.Substring(0, $full_API_string.Length - 1) + "]},param2:$($UCSDSRID)}"
        $workflow_uri_start += $full_API_string
        $sr_uris.Add($workflow_uri_start)
    }

    return $sr_uris
}

# Our custom function for initiating Invoke-WebRequest in a remote PoSH session

function Connect-NestedPSSession
{
    [CmdletBinding()]

    param(
    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$PSAServer,

    [parameter(Mandatory=$true)]
    [ValidateNotNullorEmpty()]
    [string]$PSAUser,

    [parameter(Mandatory=$true)]
    [ValidateNotNullorEmpty()]
    [SecureString]$PSAPassword,

    [parameter(Mandatory=$true)]
    [ValidateNotNullorEmpty()]
    [string]$URI,

    [parameter(Mandatory=$true)]
    [ValidateNotNullorEmpty()]
    [System.Collections.Hashtable]$Headers,

    [parameter(Mandatory=$true)]
    [ValidateNotNullorEmpty()]
    [string]$Method

    )

    $the_user = $PSAUser
    $the_cred = New-Object -Type System.Management.Automation.PSCredential -ArgumentList $the_user, $PSAPassword

    $the_session = New-PSSession -ComputerName $PSAServer -Credential $the_cred
    $response = Invoke-Command -Session $the_session -ScriptBlock { Invoke-WebRequest -Uri $args[0] -Headers $args[1] -Method $args[2] } -ArgumentList $URI, $Headers, $Method
    $remove_session = $the_session | Disconnect-PSSession | Remove-PSSession

    return $response
}

#====================================================================
#       MAIN SCRIPT BODY
#    Also, our list of arguments coming into the script from UCSD
#====================================================================

$site = $args[0]
$find_vlan = $args[1]
$vlan_name = $args[2]
$ucsd_group = $args[3]
$ucsd_sr_id = $args[4]
$global:ucsd_psa_server = $args[5]
$global:ucsd_psa_user = $args[6]
$global:ucsd_psa_pass = ConvertTo-SecureString -String $args[7] -AsPlainText -Force

# Setting the X-Cloupia-Request-Key header for use with all of our northbound API calls

$headers = @{}
$headers.Add("X-Cloupia-Request-Key","INSERT YOUR API ACCESS KEY FROM UCSD")

# This section gets the list of all the VLANs in inventory on the networking devices at a particular site

$uri = "https://your.ucsd.url.com/app/api/rest?opName=userAPIGetTabularReport&opData={param0:`"23`",param1:`"$($site)`",param2:`"VLANS-T52`"}"
$response = Connect-NestedPSSession -PSAServer $ucsd_psa_server -PSAUser $ucsd_psa_user -PSAPassword $ucsd_psa_pass -Uri $uri -Headers $headers -Method Get
$response = ParseJsonString($response.Content)
$vlans = $response.serviceResult.rows | ? Device_IP -notmatch "san" | Select Device_IP, VLAN_ID | Sort-Object Device_IP
$response = $null

# This section performs a northbound API call to get all the switches registered to that site in UCS Director (which are labeled as LSW or SSW by name)

$uri2 = "https://your.ucsd.url.com/app/api/rest?opName=userAPIGetTabularReport&opData={param0:`"23`",param1:`"$($site)`",param2:`"MANAGED-NETWORK-ELEMENTS-T52`"}"
$response2 = Connect-NestedPSSession -PSAServer $ucsd_psa_server -PSAUser $ucsd_psa_user -PSAPassword $ucsd_psa_pass -Uri $uri2 -Headers $headers -Method Get
$response2 = ParseJsonString($response2.Content)
$nxos_devices = $response2.serviceResult.rows | ? Name -match "LSW|SSW" | Select Device_IP, Name, Model | Sort-Object Name
$response2 = $null

$5k_switch_list = ""
$7k_switch_list = ""
$5k_rollback_list = ""
$7k_rollback_list = ""

# This next section checks to see if the VLAN tag already exists on a switch and determines which type of switch it is

foreach ($nxos_device in $nxos_devices)
{
    $blah = $vlans | ? {(($_.Device_IP -eq $nxos_device.Device_IP) -and ($_.VLAN_ID -eq $find_vlan))}
    if ($blah.Count -eq 0)
    {
        if ($nxos_device.Model -match "Nexus7000")
        {
            if ($7k_switch_list -eq "")  { $var_netdevice = $site + "@" + $nxos_device.Device_IP }
            else { $var_netdevice = "," + $site + "@" + $nxos_device.Device_IP }
            $7k_switch_list += $var_netdevice
        }
        
        if ($nxos_device.Model -match "Nexus5548")
        {
            if ($5k_switch_list -eq "")  { $var_netdevice = $site + "@" + $nxos_device.Device_IP }
            else { $var_netdevice = "," + $site + "@" + $nxos_device.Device_IP }
            $5k_switch_list += $var_netdevice
        }
    }
    else
    {
        if ($nxos_device.Model -match "Nexus7000")
        {
            if ($7k_rollback_list -eq "") { $var_netdevice = $site + "@" + $nxos_device.Device_IP }
            else { $var_netdevice = "," + $site + "@" + $nxos_device.Device_IP }
            $7k_rollback_list += $var_netdevice
        }
        if ($nxos_device.Model -match "Nexus5548")
        {
            if ($5k_rollback_list -eq "")  { $var_netdevice = $site + "@" + $nxos_device.Device_IP }
            else { $var_netdevice = "," + $site + "@" + $nxos_device.Device_IP }
            $5k_rollback_list += $var_netdevice
        }
    }
}

# In larger inventories, the vlan and nxos_devices variables can get rather large, blanking them out to save memory in the PoSH session

$vlan = $null
$nxos_devices = $null

# Retrieve all the URIs from each of the four possible conditions

if ($7k_switch_list -ne "") { $7k_add_uris = Get-UCSDURIs -NexusList $7k_switch_list -VLANName $vlan_name -VLANID $find_vlan -NexusModel "7K" -UCSDGroup $ucsd_group -UCSDWorkflow "Nexus List Add" -UCSDSRID $ucsd_sr_id}
if ($5k_switch_list -ne "") { $5k_add_uris = Get-UCSDURIs -NexusList $5k_switch_list -VLANName $vlan_name -VLANID $find_vlan -NexusModel "5K" -UCSDGroup $ucsd_group -UCSDWorkflow "Nexus List Add" -UCSDSRID $ucsd_sr_id}
if ($7k_rollback_list -ne "") { $7k_rollback_uris = Get-UCSDURIs -NexusList $7k_rollback_list -VLANName $vlan_name -VLANID $find_vlan -NexusModel "7K" -UCSDGroup $ucsd_group -UCSDWorkflow "Nexus List Rollback Setup" -UCSDSRID $ucsd_sr_id}
if ($5k_rollback_list -ne "") { $5k_rollback_uris = Get-UCSDURIs -NexusList $5k_rollback_list -VLANName $vlan_name -VLANID $find_vlan -NexusModel "5K" -UCSDGroup $ucsd_group -UCSDWorkflow "Nexus List Rollback Setup" -UCSDSRID $ucsd_sr_id}

# Create SR Table Hashtable and create a null valued variable for storing the URIs into

$sr_table = @{}
$all_uris = $null

#   Add all the URIs back into a master list for processing

if ($7k_add_uris -ne $null) { $all_uris += $7k_add_uris }
if ($5k_add_uris -ne $null) { $all_uris += $5k_add_uris }
if ($7k_rollback_uris -ne $null) { $all_uris += $7k_rollback_uris }
if ($5k_rollback_uris -ne $null) { $all_uris += $5k_rollback_uris }

# Process each URI and store the SR ID into a hashtable to keep an eye on the workflow execution status

foreach($uri in $all_uris)
{
    $response = Connect-NestedPSSession -PSAServer $ucsd_psa_server -PSAUser $ucsd_psa_user -PSAPassword $ucsd_psa_pass -Uri $uri -Headers $headers -Method Get
    $response = ParseJsonString($response.Content)
    $sr_table["$($response.serviceResult)"] = $response.serviceResult
}

# Determine how many SRs we initiated and create a new string to hold the SR IDs in a comma delimited fashion

$total_srs = $sr_table.Count
$sr_list = ""

# This section continually goes through our list of SRs and if the status is one that the workflow completed, we remove it from the list.
# This section completes when all SRs have been removed from the hashtable

while ($total_srs -gt 0)
{
    foreach($sr in ($sr_table.GetEnumerator() | Sort-Object Name))
    {
        $lookup_uri = "https://your.ucsd.url.com/app/api/rest?formatType=json&opName=userAPIGetWorkflowStatus&opData={param0:$($sr.Name)}"
        $response = Connect-NestedPSSession -PSAServer $ucsd_psa_server -PSAUser $ucsd_psa_user -PSAPassword $ucsd_psa_pass -Uri $lookup_uri -Headers $headers -Method Get
        $response = ParseJsonString($response.Content)
        $code = $response.serviceResult
        if ($code -match "0|1|6") { }
        elseif ($code -match "2|3|4|5|7")
        {
            if ($sr_list -eq "") { $sr_list = $sr.Name }
            else { $sr_list += "," + $sr.Name }
            $sr_table.Remove($sr.Name)
            $total_srs--
        }
    }
    if ($total_srs -eq 0)  { break; }
    else
    {  Start-Sleep 10  }
}

# Our generated list of SRs to be given back to UCS Director for rollback capabilities in another script

return $sr_list
