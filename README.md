# Overview
When building a Function App API in Azure that accepts incoming HTTP requests from an Entra ID joined devices, being able to validate such a request is only coming from a trusted device in a given Entra ID tenant adds extensive security to the API. By default, the Function App can be configured to only accept incoming requests with a valid client certificate, which is a good security practice. Although, there's also another option to enhance the security of a Function App in terms of validating the incoming request, using the certificate enrolled to the device when it first registered itself with Entra ID.

This module performs the device trust validation and can be embedded in most Function Apps where enhanced request validation is required.

# How the trusted device validation works

Every Entra ID joined or hybrid Entra ID joined device has a computer certificate that was enrolled when registering the device to Entra ID. This device specific computer certificate's public and private keys are available locally on the device, while the public key is known to Entra ID. The device trust validation functionality occurs in the following scenarios:

- Client-side data gathering
- Function App data validation

## Client-side

On the client-side, the module performs a series of operations to gather and prepare cryptographic proof that the request is originating from a trusted Entra ID device. The `New-EntraIDDeviceTrustBody` function orchestrates this entire data gathering process:

1. **Device ID Retrieval**: The module queries the local device's registry at `HKLM:\SYSTEM\CurrentControlSet\Control\CloudDomainJoin\JoinInfo` to locate the Entra ID device registration certificate. The device identifier (DeviceID) is extracted from the certificate's subject name, which uniquely identifies this device in Entra ID.

2. **Certificate Thumbprint Extraction**: The thumbprint of the Entra ID registration certificate is retrieved from the registry. This thumbprint serves as a unique identifier for the specific certificate that was enrolled during device registration.

3. **Public Key Export**: The public key from the device registration certificate is extracted as a byte array and encoded as a Base64 string. This public key will be used by the Function App to verify the cryptographic signature.

4. **Signature Generation**: Using the private key of the device registration certificate (stored securely in the LocalMachine certificate store), the module creates a cryptographic signature. The DeviceID is used as the content to be signed: it is first converted to bytes using UTF8 encoding, then a SHA256 hash is computed, and finally the hash is signed using RSA with PKCS1 padding. The resulting signature is encoded as a Base64 string.

All of these elements—the device name, DeviceID, certificate thumbprint, public key, and signature—are combined into a hash table object that forms the body of the HTTP request sent to the Function App. This cryptographic proof allows the Function App to verify that the request genuinely originates from the specific trusted device.

## Function App

On the Function App side, the module receives the incoming request containing the Entra ID device identifier (DeviceID), certificate thumbprint, Base64 encoded public key, and the cryptographic signature from the client. The module performs a multi-stage validation process to ensure the request originates from a trusted Entra ID device:

1. **Device Record Retrieval**: Using Microsoft Graph API, the Function App retrieves the Entra ID device record based on the DeviceID sent from the client. This record contains the alternativeSecurityIds property which holds the device's certificate information registered with Entra ID.

2. **Thumbprint Validation**: The certificate thumbprint from the client request is validated against the thumbprint stored in the device record's alternativeSecurityIds property using the `Test-EntraIDDeviceAlternativeSecurityIds` function.

3. **Public Key Hash Validation**: The public key sent from the client is hashed using SHA256 and compared against the public key hash stored in the device record's alternativeSecurityIds property to ensure it matches the certificate known to Entra ID.

4. **Signature Verification**: The cryptographic signature created by the client using its private key is verified using the public key. The `Test-Encryption` function reconstructs the RSA public key from the client-provided bytes and verifies that the signature was indeed created with the corresponding private key by validating the signed content (the DeviceID) against the signature.

5. **Device Status Check**: Finally, the module validates that the device record is not disabled in Entra ID by checking the accountEnabled property.

If all validation steps pass successfully, the Function App can trust that the request came from the specific Entra ID joined or hybrid Entra ID joined device and proceed with processing the request. If any validation step fails, the Function App returns an HTTP 403 Forbidden status code, rejecting the untrusted request.

# How to use EntraIDDeviceTrust.Client module in a client-side script
Ensure the EntraIDDeviceTrust.Client module is installed on the device prior to running the sample code below. Use the `Test-EntraIDDeviceRegistration` function to ensure the device where the code is running on fulfills the device registration requirements. Then use the `New-EntraIDDeviceTrustBody` function to automatically generate a hash-table object containing the gathered data required for the body of the request. Finally, use built-in `Invoke-RestMethod` cmdlet to invoke the request against the Function App, passing the gathered data to be validated by the Function App, if the request comes from a trusted device.

```PowerShell
if (Test-EntraIDDeviceRegistration -eq $true) {
    # Create body for Function App request
    $BodyTable = New-EntraIDDeviceTrustBody

    # Extend body table with custom data to be processed by Function App
    # ...

    # Send log data to Function App
    $URI = "https://<function_app_name>.azurewebsites.net/api/<function_name>?code=<function_key>"
    Invoke-RestMethod -Method "POST" -Uri $URI -Body ($BodyTable | ConvertTo-Json) -ContentType "application/json"
}
else {
    Write-Warning -Message "Script is not running on an Entra ID joined or hybrid Entra ID joined device"
}
```

For a full sample of the client-side script, explore the code in \Samples\ClientSide.ps1 in this repo.

# How to use EntraIDDeviceTrust.FunctionApp module in a Function App
Enable the module to be installed as a managed dependency by editing your requirements.psd1 file of the Function App, e.g. as shown below:

```PowerShell
@{
    'EntraIDDeviceTrust.FunctionApp' = '1.*'
}
```

Another option would also be to clone this module from GitHub and include it in the modules folder of your Function App, to embedd it directly and not have a dependency to PSGallery.

For a full sample Function App function, explore the code in \Samples\FunctionApp-MSI.ps1 in this repo.
