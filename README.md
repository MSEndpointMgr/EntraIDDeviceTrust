# Overview
When building a Function App API in Azure that accepts incoming HTTP requests from an Entra ID joined devices, being able to validate such a request is only coming from a trusted device in a given Entra ID tenant adds extensive security to the API. By default, the Function App can be configured to only accept incoming requests with a valid client certificate, which is a good security practice. Although, there's also another option to enhance the security of a Function App in terms of validating the incoming request, using the certificate enrolled to the device when it first registered itself with Entra ID.

This module performs the device trust validation and can be embedded in most Function Apps where enhanced request validation is required.

# How the trusted device validation works

Every Entra ID joined or hybrid Entra ID joined device has a computer certificate that was enrolled when registering the device to Entra ID. This device specific computer certificate's public and private keys are available locally on the device, while the public key is known to Entra ID. The device trust validation functionality occurs in the following scenarios:

- Client-side data gathering
- Function App data validation

## Client-side

On the client-side, a signature hash using the private key of the computer certificate is calculated and sent encoded as a Base64 string to the Function App including the Entra ID device identifier (the common name of the computer certificate), the public key as a byte array encoded as a Base64 string together with the computer certificate thumbprint. These data strings are sent all together as parameter input when calling the Function App API

## Function App

To be added...

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
