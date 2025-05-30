<#
.SYNOPSIS
    Generates a random password with customizable length and character sets.
    Optionally encodes the generated password into a Base64 string.

.DESCRIPTION
    This function creates a strong, random password by combining characters
    from specified pools (uppercase, lowercase, numbers, symbols).
    It ensures that at least one character from each selected pool is included
    to meet common complexity requirements.

    The generated password can be returned as a plain string or as a Base64 encoded string.

.PARAMETER Length
    The desired length of the generated password.
    Defaults to 16 characters.

.PARAMETER IncludeUppercase
    Specifies whether to include uppercase letters (A-Z) in the password.
    Defaults to $true.

.PARAMETER IncludeLowercase
    Specifies whether to include lowercase letters (a-z) in the password.
    Defaults to $true.

.PARAMETER IncludeNumbers
    Specifies whether to include numbers (0-9) in the password.
    Defaults to $true.

.PARAMETER IncludeSymbols
    Specifies whether to include common symbols (!@#$%^&*()_+-=[]{}|;:,.<>?) in the password.
    Defaults to $true.

.PARAMETER HashPassword
    If set to $true, the function will return a SHA256 hash of the generated password
    instead of the plain text password.

.EXAMPLE
    # Generate a 12-character password with default character sets
    New-Password -Length 12

.EXAMPLE
    # Generate a 20-character password including only letters and numbers
    New-Password -Length 20 -IncludeSymbols $false

.EXAMPLE
    # Generate a 16-character password and encode it
    New-Password -Length 16 -HashPassword

.EXAMPLE
    # Generate a password with specific character sets and encode it
    New-Password -Length 10 -IncludeUppercase $true -IncludeNumbers $true -IncludeLowercase $false -IncludeSymbols $false -HashPassword
#>
function New-Password {
    [CmdletBinding()]
    [OutputType([string])]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions','', Justification='Does not change system state.')]
    param(
        [Parameter()]
        [int]$Length = 16,

        [Parameter()]
        [bool]$IncludeUppercase = $true,

        [Parameter()]
        [bool]$IncludeLowercase = $true,

        [Parameter()]
        [bool]$IncludeNumbers = $true,

        [Parameter()]
        [bool]$IncludeSymbols = $true,

        [Parameter()]
        [switch]$HashPassword
    )

    # Define character pools
    $uppercaseChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.ToCharArray()
    $lowercaseChars = 'abcdefghijklmnopqrstuvwxyz'.ToCharArray()
    $numberChars = '0123456789'.ToCharArray()
    $symbolChars = '!@#$%^&*()_+-=[]{}|;:,.<>/?'.ToCharArray()

    $allChars = @()
    $requiredChars = @() # To ensure at least one from each selected pool

    if ($IncludeUppercase) {
        $allChars += $uppercaseChars
        $requiredChars += $uppercaseChars | Get-Random
    }
    if ($IncludeLowercase) {
        $allChars += $lowercaseChars
        $requiredChars += $lowercaseChars | Get-Random
    }
    if ($IncludeNumbers) {
        $allChars += $numberChars
        $requiredChars += $numberChars | Get-Random
    }
    if ($IncludeSymbols) {
        $allChars += $symbolChars
        $requiredChars += $symbolChars | Get-Random
    }

    # Validate that at least one character set is selected
    if ($allChars.Count -eq 0) {
        Write-Error 'At least one character set (uppercase, lowercase, numbers, or symbols) must be included.'
        return
    }

    # Ensure password length is at least the number of required character types
    if ($Length -lt $requiredChars.Count) {
        Write-Warning "Password length ($Length) is less than the number of required character types ($($requiredChars.Count)). Adjusting length to $($requiredChars.Count)."
        $Length = $requiredChars.Count
    }

    # Generate the remaining characters
    $random = New-Object System.Random
    $passwordChars = New-Object char[] $Length

    # Place required characters first
    for ($i = 0; $i -lt $requiredChars.Count; $i++) {
        $passwordChars[$i] = $requiredChars[$i]
    }

    # Fill the rest of the password length with random characters from all selected pools
    for ($i = $requiredChars.Count; $i -lt $Length; $i++) {
        $randomIndex = $random.Next(0, $allChars.Count)
        $passwordChars[$i] = $allChars[$randomIndex]
    }

    # Shuffle the password characters to randomize the position of required characters
    for ($i = $Length - 1; $i -gt 0; $i--) {
        $j = $random.Next(0, $i + 1)
        $temp = $passwordChars[$i]
        $passwordChars[$i] = $passwordChars[$j]
        $passwordChars[$j] = $temp
    }

    $password = -join $passwordChars

    if ($HashPassword) {
        # Generate a random salt
        $saltBytes = New-Object byte[] 16
        $random.NextBytes($saltBytes)
        $salt = [System.Convert]::ToBase64String($saltBytes)

        # Combine password and salt
        $saltedPasswordBytes = $utf8.GetBytes("${salt}:${password}")

        # Hash the salted password
        $hashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $hashAlgorithm.ComputeHash($saltedPasswordBytes)
        $hashedPassword = [System.BitConverter]::ToString($hashBytes).Replace('-', '')

        # Return the salt and the hash (you'd typically store the salt with the hash)
        return "${salt}:${hashedPassword}"
    } else {
        return $password
    }
}
