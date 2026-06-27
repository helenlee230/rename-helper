param(
    [Parameter(Mandatory)]
    [string]$Prompt,

    [Parameter(Mandatory)]
    [string]$Key,

    [string]$Model = "gpt-4.1-mini"
)

$body = @{
    model = $Model
    messages = @(
        @{
            role = "user"
            content = $Prompt
        }
    )
} | ConvertTo-Json -Depth 5

try {
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)

    $response = Invoke-RestMethod `
        -Uri "https://api.openai.com/v1/chat/completions" `
        -Method Post `
        -Headers @{
            Authorization = "Bearer $Key"
        } `
        -ContentType "application/json; charset=utf-8" `
        -Body $bodyBytes

    $response.choices[0].message.content.Trim()
}
catch {
    Write-Error $_
    exit 1
}