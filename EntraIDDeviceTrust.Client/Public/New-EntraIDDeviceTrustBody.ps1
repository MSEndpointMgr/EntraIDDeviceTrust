function New-EntraIDDeviceTrustBody {
    <#
    .SYNOPSIS
        Construct the body with the elements for a sucessful device trust validation required by a Function App that's leveraging the EntraIDDeviceTrust.FunctionApp module.

    .DESCRIPTION
        Construct the body with the elements for a sucessful device trust validation required by a Function App that's leveraging the EntraIDDeviceTrust.FunctionApp module.

    .EXAMPLE
        .\New-EntraIDDeviceTrustBody.ps1

    .NOTES
        Author:      Nickolaj Andersen
        Contact:     @NickolajA
        Created:     2022-03-14
        Updated:     2026-08-25 (Anders Ahl)

        Version history:
        1.0.0 - (2022-03-14) Script created
        1.0.1 - (2026-08-25) Added Timestamp and Nonce to the signed content to prevent replay of a captured request
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    Process {
        # Retrieve required data for building the request body
        $EntraIDDeviceID = Get-EntraIDDeviceID
        $CertificateThumbprint = Get-EntraIDRegistrationCertificateThumbprint
        $PublicKeyBytesEncoded = Get-PublicKeyBytesEncodedString -Thumbprint $CertificateThumbprint

        # Generate a per-request timestamp and nonce ("salt") so the signed content, and therefore the
        # signature, is unique for every request. This allows the receiving side to reject stale or
        # previously seen requests instead of trusting a static signature that could be replayed indefinitely.
        $Timestamp = [DateTime]::UtcNow.ToString("o")
        $Nonce = [System.Guid]::NewGuid().ToString()

        # Combine device identifier, timestamp and nonce into the content that gets signed
        $ContentToSign = "$($EntraIDDeviceID)|$($Timestamp)|$($Nonce)"
        $Signature = New-RSACertificateSignature -Content $ContentToSign -Thumbprint $CertificateThumbprint

        # Construct client-side request header
        $BodyTable = [ordered]@{
            DeviceName = $env:COMPUTERNAME
            DeviceID = $EntraIDDeviceID
            Timestamp = $Timestamp
            Nonce = $Nonce
            Signature = $Signature
            Thumbprint = $CertificateThumbprint
            PublicKey = $PublicKeyBytesEncoded
        }

        # Handle return value
        return $BodyTable
    }
}