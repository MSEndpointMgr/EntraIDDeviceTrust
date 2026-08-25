function Test-EntraIDDeviceTrustTimestamp {
    <#
    .SYNOPSIS
        Validate that a Timestamp value sent from a client is well-formed and within an acceptable freshness window.

    .DESCRIPTION
        Validate that a Timestamp value sent from a client is well-formed and within an acceptable freshness window.
        Used together with the Nonce value and a signature covering "DeviceID|Timestamp|Nonce" to prevent a captured
        request from being replayed once the tolerance window has elapsed. This check alone does not guarantee a
        request can only be used once within the tolerance window - pair it with a persisted nonce store (e.g. Azure
        Table Storage, Redis or Cosmos DB) keyed on DeviceID+Nonce if strict single-use enforcement is required.

    .PARAMETER Timestamp
        Specify the Timestamp property sent from the client, expected in round-trip ("o") DateTime format.

    .PARAMETER ToleranceInMinutes
        Specify the allowed clock skew, in minutes, between the client-supplied timestamp and the current UTC time. Defaults to 5 minutes.

    .NOTES
        Author:      Anders Ahl
        Created:     2026-08-25
        Updated:     2026-08-25

        Version history:
        1.0.0 - (2026-08-25) Function created
    #>
    param(
        [parameter(Mandatory = $true, HelpMessage = "Specify the Timestamp property sent from the client, expected in round-trip (o) DateTime format.")]
        [ValidateNotNullOrEmpty()]
        [string]$Timestamp,

        [parameter(Mandatory = $false, HelpMessage = "Specify the allowed clock skew, in minutes, between the client-supplied timestamp and the current UTC time.")]
        [ValidateRange(1, 1440)]
        [int]$ToleranceInMinutes = 5
    )
    Process {
        $ParsedTimestamp = [DateTime]::MinValue
        $IsValidFormat = [DateTime]::TryParse($Timestamp, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$ParsedTimestamp)
        if ($IsValidFormat -eq $false) {
            return $false
        }

        # Reject timestamps that are not clearly expressed in UTC to avoid ambiguous local-time comparisons
        if ($ParsedTimestamp.Kind -ne [System.DateTimeKind]::Utc) {
            return $false
        }

        # Compare against the current UTC time, allowing for the configured clock skew in either direction
        $Difference = ([DateTime]::UtcNow - $ParsedTimestamp).Duration()
        if ($Difference.TotalMinutes -gt $ToleranceInMinutes) {
            return $false
        }

        return $true
    }
}
