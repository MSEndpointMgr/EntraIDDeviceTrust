function Test-Encryption {
    <#
    .SYNOPSIS
        Test the signature created with the private key by using the public key.
    
    .DESCRIPTION
        Test the signature created with the private key by using the public key.

    .PARAMETER PublicKeyEncoded
        Specify the Base64 encoded string representation of the Public Key.

    .PARAMETER Signature
        Specify the Base64 encoded string representation of the signature coming from the inbound request.

    .PARAMETER Content
        Specify the content string that the signature coming from the inbound request is based upon, e.g. "DeviceID|Timestamp|Nonce".

    .NOTES
        Author:      Nickolaj Andersen / Thomas Kurth
        Contact:     @NickolajA
        Created:     2021-06-07
        Updated:     2026-08-25 (Anders Ahl)

        Version history:
        1.0.0 - (2021-06-07) Function created
        1.0.1 - (2026-08-25) Replaced manual modulus/exponent byte parsing with RSA.ImportRSAPublicKey, which correctly
                             handles keys of any size and exponent length instead of assuming a 2048-bit modulus and
                             a 3-byte exponent

        Credits to Thomas Kurth for sharing his original C# code.
    #>
    param(
        [parameter(Mandatory = $true, HelpMessage = "Specify the Base64 encoded string representation of the Public Key.")]
        [ValidateNotNullOrEmpty()]
        [string]$PublicKeyEncoded,

        [parameter(Mandatory = $true, HelpMessage = "Specify the Base64 encoded string representation of the signature coming from the inbound request.")]
        [ValidateNotNullOrEmpty()]
        [string]$Signature,

        [parameter(Mandatory = $true, HelpMessage = "Specify the content string that the signature coming from the inbound request is based upon.")]
        [ValidateNotNullOrEmpty()]
        [string]$Content
    )
    Process {
        # Convert from Base64 string to byte array
        $PublicKeyBytes = [System.Convert]::FromBase64String($PublicKeyEncoded)

        # Convert signature from Base64 string
        [byte[]]$Signature = [System.Convert]::FromBase64String($Signature)

        # Reconstruct the RSA public key directly from the PKCS#1 encoded bytes returned by
        # X509Certificate2.GetPublicKey(). This avoids manually slicing modulus/exponent bytes at
        # fixed offsets, which only worked for exactly 2048-bit keys with a 3-byte exponent.
        $RSA = [System.Security.Cryptography.RSA]::Create()
        try {
            $BytesRead = 0
            $RSA.ImportRSAPublicKey($PublicKeyBytes, [ref]$BytesRead)

            # Construct a new SHA256 object to be used when computing the hash
            $SHA256 = [System.Security.Cryptography.SHA256]::Create()

            # Construct new UTF8 unicode encoding object
            $UnicodeEncoding = [System.Text.UnicodeEncoding]::UTF8

            # Convert content to byte array
            [byte[]]$EncodedContentData = $UnicodeEncoding.GetBytes($Content)

            # Compute the hash
            [byte[]]$ComputedHash = $SHA256.ComputeHash($EncodedContentData)

            # Verify the signature with the computed hash of the content using the public key
            return $RSA.VerifyHash($ComputedHash, $Signature, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        }
        finally {
            $RSA.Dispose()
        }
    }
}