param(
    [Parameter(Mandatory)]
    [string]$Folder
)
Add-Type -AssemblyName System.Windows.Forms

$pdfToText = Join-Path $PSScriptRoot "pdftotext.exe"
$askScript = Join-Path $PSScriptRoot "ask.ps1"
$rulesFile = Join-Path $PSScriptRoot "naming-rules.txt"
$adjustmentPromptFile = Join-Path $PSScriptRoot "adjustment-prompt.txt"

if (!(Test-Path $Folder)) {
    Write-Error "Folder '$Folder' does not exist."
    exit 1
}

if (!(Test-Path $pdfToText)) {
    Write-Error "pdftotext.exe not found: $pdfToText"
    exit 1
}

if (!(Test-Path $askScript)) {
    Write-Error "ask.ps1 not found: $askScript"
    exit 1
}

if (!(Test-Path $rulesFile)) {
    Write-Error "naming-rules.txt not found: $rulesFile"
    exit 1
}

if (!(Test-Path $adjustmentPromptFile)) {
    Write-Error "adjustment-prompt.txt not found: $adjustmentPromptFile"
    exit 1
}

$namingRules = Get-Content $rulesFile -Raw
$adjustmentPrompt = Get-Content $adjustmentPromptFile -Raw

Get-ChildItem -Path $Folder -Filter *.pdf | ForEach-Object {

    $file = $_

    Clear-Host

    Write-Host "===================================================="
    Write-Host "Current file: $($file.Name)"
    Write-Host "===================================================="
    Write-Host

    # Extract first page
    $text = & $pdfToText -simple -f 1 -l 1 $file.FullName -

    # Remove NUL characters
    $text = $text -replace "`0", ""

    # Normalize smart quotes and weird punctuation (optional but recommended)
    # $text = $text -replace 'â€™', "'"
    # $text = $text -replace 'â€œ|â€', '"'
    # $text = $text -replace 'â€“|â€”', "-"

    # Remove other control characters except CR/LF/TAB
    $text = [regex]::Replace($text, '[\x00-\x08\x0B\x0C\x0E-\x1F]', '')

    $text = $text -replace "`0", ""
    $text = [Text.Encoding]::UTF8.GetString(
        [Text.Encoding]::GetEncoding("UTF-8").GetBytes($text)
    )

    Write-Host $file
    Write-Host $file.FullName

    & chrome.exe $file.FullName

    # Write-Host $text
    Write-Host
    Write-Host "----------------------------------------------------"
    Write-Host "Generating filename..."
    Write-Host

    $prompt = @"
$namingRules

PDF CONTENT:

$text

Respond with ONLY the filename, without the .pdf extension.
"@


    $suggestedName = & $askScript -prompt $prompt -key $Env:OPENAI_KEY
    $suggestedName = ($suggestedName | Out-String).Trim()

    Write-Host
    Write-Host "Suggested filename:"
    Write-Host "  $suggestedName"
    Write-Host

    $loop = $true

    while ($loop) {

        $choice = Read-Host "[A]ccept  [E]dit  [S]kip  [Q]uit  [M]odify"

        switch ($choice.ToUpper()) {

            "A" {
                $newName = $suggestedName
                $loop = $false
                break
            }

            "E" {
                # Send keystrokes to the console buffer to simulate typing the default value
                $wshell = New-Object -ComObject WScript.Shell
                $wshell.SendKeys($suggestedName)

                $userInput = Read-Host -Prompt "Filename (without .pdf)"

                # Fallback in case of empty input
                if (![string]::IsNullOrWhiteSpace($userInput)) {
                    $newName = $userInput
                }   

                # $newName = Read-Host "Filename (without .pdf)"
                $loop = $false
                break
            }

            "M" {
                $adjustmentInstructions = Read-Host "How would you like me to adjust the filename? "

                $prompt = @"
$adjustmentPrompt

PDF CONTENT:

$text

HERE IS THE FILENAME YOU PREVIOUSLY SUGGESTED:

$suggestedName

HERE IS HOW I NEED YOU TO MODIFY THE SUGGESTED FILENAME:

$adjustmentInstructions
"@
                $suggestedName = & $askScript -prompt $prompt -key $Env:OPENAI_KEY

                Write-Host
                Write-Host "Suggested filename:"
                Write-Host "  $suggestedName"
                Write-Host
                break
            }

            "S" {
                # empty name to skip renaming
                $newName = ''
                $loop = $false
                break 
            }

            "Q" {
                exit 0 
            }

            default {
                Write-Host "Please enter A, E, S, or Q."
            }
        }
    }

    if (![string]::IsNullOrWhiteSpace($newName)) {

        # Remove invalid filename characters
        $newName = $newName.Trim()
        $newName = [regex]::Replace(
            $newName,
            "[{0}]+" -f [regex]::Escape(([IO.Path]::GetInvalidFileNameChars() -join "")),
            "_"
        )

        $newFilename = "$newName.pdf"

        Rename-Item -LiteralPath $file.FullName -NewName $newFilename

        Write-Host
        Write-Host "Renamed to:"
        Write-Host "  $newFilename"
        Write-Host

        Pause
    }
}