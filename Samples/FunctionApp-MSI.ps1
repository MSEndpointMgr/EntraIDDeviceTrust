using namespace System.Net

# Input bindings are passed in via param block.
param(
    [Parameter(Mandatory = $true)]
    $Request,

    [Parameter(Mandatory = $false)]
    $TriggerMetadata
)

# Functions
function Get-AuthToken {
    <#
    .SYNOPSIS
        Retrieve an access token for the Managed System Identity.
    
    .DESCRIPTION
        Retrieve an access token for the Managed System Identity.
    
    .NOTES
        Author:      Nickolaj Andersen
        Contact:     @NickolajA
        Created:     2021-06-07
        Updated:     2026-08-25 (Anders Ahl)
    
        Version history:
        1.0.0 - (2021-06-07) Function created
        1.0.1 - (2026-08-25) Migrated from deprecated MSI_ENDPOINT/MSI_SECRET to IDENTITY_ENDPOINT/IDENTITY_HEADER (api-version 2019-08-01)
    #>
    Process {
        # Get Managed Service Identity details from the Azure Functions application settings.
        # IDENTITY_ENDPOINT/IDENTITY_HEADER (API version 2019-08-01) is the current App Service/Functions
        # managed identity contract - the legacy MSI_ENDPOINT/MSI_SECRET (2017-09-01) variables are deprecated.
        $IdentityEndpoint = $env:IDENTITY_ENDPOINT
        $IdentityHeader = $env:IDENTITY_HEADER

        # Define the required URI and token request params
        $APIVersion = "2019-08-01"
        $ResourceURI = "https://graph.microsoft.com"
        $AuthURI = "$($IdentityEndpoint)?resource=$($ResourceURI)&api-version=$($APIVersion)"

        # Call resource URI to retrieve access token as Managed Service Identity
        $Response = Invoke-RestMethod -Uri $AuthURI -Method "Get" -Headers @{ "X-IDENTITY-HEADER" = "$($IdentityHeader)" } -ErrorAction Stop

        # Construct authentication header to be returned from function
        $AuthenticationHeader = @{
            "Authorization" = "Bearer $($Response.access_token)"
            "ExpiresOn" = $Response.expires_on
        }

        # Handle return value
        return $AuthenticationHeader
    }
}

# Retrieve authentication token
$AuthToken = Get-AuthToken

# Initate variables
$StatusCode = [HttpStatusCode]::OK
$Body = [string]::Empty

# Assign incoming request properties to variables
$DeviceName = $Request.Body.DeviceName
$DeviceID = $Request.Body.DeviceID
$Timestamp = $Request.Body.Timestamp
$Nonce = $Request.Body.Nonce
$Signature = $Request.Body.Signature
$Thumbprint = $Request.Body.Thumbprint
$PublicKey = $Request.Body.PublicKey

# Validate that all required properties were supplied before attempting any validation logic
$RequiredProperties = @("DeviceName", "DeviceID", "Timestamp", "Nonce", "Signature", "Thumbprint", "PublicKey")
$MissingProperties = $RequiredProperties | Where-Object { [string]::IsNullOrWhiteSpace($Request.Body.$PSItem) }
if ($MissingProperties.Count -gt 0) {
    Write-Warning -Message "Request rejected, missing required propert(ies): $($MissingProperties -join ", ")"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::BadRequest
        Body = "Bad request"
    })
    return
}

# Initiate request handling
Write-Output -InputObject "Initiating request handling for device named as '$($DeviceName)' with identifier: $($DeviceID)"

# Validate the request timestamp before doing any further work, rejecting stale or clock-skewed requests
if (-not (Test-EntraIDDeviceTrustTimestamp -Timestamp $Timestamp -ToleranceInMinutes 5)) {
    Write-Warning -Message "Trusted Entra ID device record validation for inbound request failed, timestamp is missing, malformed or outside of the allowed tolerance window"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Forbidden
        Body = "Untrusted request"
    })
    return
}

# Signed content must match exactly what the client signed, refer to New-EntraIDDeviceTrustBody
$SignedContent = "$($DeviceID)|$($Timestamp)|$($Nonce)"

try {
    # Retrieve Entra ID device record based on DeviceID property from incoming request body
    $EntraIDDeviceRecord = Get-EntraIDDeviceRecord -DeviceID $DeviceID -AuthToken $AuthToken
}
catch [System.Exception] {
    Write-Warning -Message "Failed to retrieve Entra ID device record for deviceId '$($DeviceID)' with error: $($_.Exception.Message)"
    $EntraIDDeviceRecord = $null
}

if ($EntraIDDeviceRecord -ne $null) {
    Write-Output -InputObject "Found trusted Entra ID device record with object identifier: $($EntraIDDeviceRecord.id)"

    # Validate thumbprint from input request with Entra ID device record's alternativeSecurityIds details
    if (Test-EntraIDDeviceAlternativeSecurityIds -AlternativeSecurityIdKey $EntraIDDeviceRecord.alternativeSecurityIds.key -Type "Thumbprint" -Value $Thumbprint) {
        Write-Output -InputObject "Successfully validated certificate thumbprint from inbound request"

        # Validate public key hash from input request with Entra ID device record's alternativeSecurityIds details
        if (Test-EntraIDDeviceAlternativeSecurityIds -AlternativeSecurityIdKey $EntraIDDeviceRecord.alternativeSecurityIds.key -Type "Hash" -Value $PublicKey) {
            Write-Output -InputObject "Successfully validated certificate SHA256 hash value from inbound request"

            $EncryptionVerification = Test-Encryption -PublicKeyEncoded $PublicKey -Signature $Signature -Content $SignedContent
            if ($EncryptionVerification -eq $true) {
                Write-Output -InputObject "Successfully validated inbound request came from a trusted Entra ID device record"

                # Validate that the inbound request came from a trusted device that's not disabled
                if ($EntraIDDeviceRecord.accountEnabled -eq $true) {
                    Write-Output -InputObject "Entra ID device record was validated as enabled"

                    #
                    #
                    # Place your code here, at this stage incoming request has been validated as trusted
                    #
                    #
                }
                else {
                    # Response body intentionally identical to other rejection paths, so a caller cannot use it to
                    # enumerate which DeviceID values exist versus which ones are merely untrusted
                    Write-Output -InputObject "Trusted Entra ID device record validation for inbound request failed, record with deviceId '$($DeviceID)' is disabled"
                    $StatusCode = [HttpStatusCode]::Forbidden
                    $Body = "Untrusted request"
                }
            }
            else {
                Write-Warning -Message "Trusted Entra ID device record validation for inbound request failed, could not validate signed content from client"
                $StatusCode = [HttpStatusCode]::Forbidden
                $Body = "Untrusted request"
            }
        }
        else {
            Write-Warning -Message "Trusted Entra ID device record validation for inbound request failed, could not validate certificate SHA256 hash value"
            $StatusCode = [HttpStatusCode]::Forbidden
            $Body = "Untrusted request"
        }
    }
    else {
        Write-Warning -Message "Trusted Entra ID device record validation for inbound request failed, could not validate certificate thumbprint"
        $StatusCode = [HttpStatusCode]::Forbidden
        $Body = "Untrusted request"
    }
}
else {
    Write-Warning -Message "Trusted Entra ID device record validation for inbound request failed, could not find device with deviceId: $($DeviceID)"
    $StatusCode = [HttpStatusCode]::Forbidden
    $Body = "Untrusted request"
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $StatusCode
    Body = $Body
})