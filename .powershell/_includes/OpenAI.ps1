
$OutputEncoding = [System.Text.Encoding]::UTF8
function Call-OpenAI {
    param (
        [Parameter(Mandatory = $false)]
        [string]$system,
        
        # Prompt text
        [Parameter(Mandatory = $true)]
        [string]$prompt,
    
        # OpenAI API Key
        [Parameter(Mandatory = $true)]
        [string]$OPEN_AI_KEY
    )

    # Set the API endpoint and API key
    $apiUrl = "https://api.openai.com/v1/chat/completions"

    # Set default system prompt if not provided
    if ([string]::IsNullOrEmpty($system)) {
        $system = "You are a technical expert assistant that generates high-quality, structured content based on code, git diffs, or git logs using the GitMoji specification. You follow UK English conventions."
    }

    # Create the body for the API request
    $body = @{
        "model"       = "gpt-4o-mini"
        "messages"    = @(
            @{ "role" = "system"; "content" = $system },
            @{ "role" = "user"; "content" = $prompt }
        )
        "temperature" = 0
        "max_tokens"  = 16000  # Based on model's max output capacity
    } | ConvertTo-Json -Depth 10

    # Define retry parameters
    $maxRetries = 5
    $retryDelay = 4  # Initial delay in seconds

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            # Send the request to the ChatGPT API
            $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Headers @{
                "Content-Type"  = "application/json; charset=utf-8"
                "Authorization" = "Bearer $OPEN_AI_KEY"
            } -Body $body -TimeoutSec 30

            # Validate response structure
            if ($response -and $response.choices -and $response.choices.Count -gt 0 -and $response.choices[0].message) {
                return $response.choices[0].message.content
            }
            else {
                throw "Invalid response structure received from OpenAI API."
            }
        }
        catch {
            $errorMessage = $_.Exception.Message

            if ($errorMessage -match "429 \(Too Many Requests\)") {
                # API Rate Limit hit; apply exponential backoff
                Write-WarningLog "Rate limit exceeded. Retrying in $retryDelay seconds..."
                Start-Sleep -Seconds $retryDelay
                $retryDelay *= 2  # Exponential backoff
            }
            elseif ($errorMessage -match "500|502|503|504") {
                # Handle server errors
                Write-WarningLog "Server error encountered. Retrying in $retryDelay seconds..."
                Start-Sleep -Seconds $retryDelay
                $retryDelay *= 2
            }
            else {
                # Non-retryable errors
                Write-Error "API call failed: $errorMessage"
                return $null
            }
        }
    }

    Write-Error "Max retries reached. Unable to get a valid response from OpenAI."
    return $null
}


function Get-TokenEstimate {
    param ($text)
    return ($text.Length / 4)  # Rough estimate, adjust as needed
}

function Get-TextChunks {
    param ($text, $maxLength)

    $chunks = @()
    $remainingText = $text

    while ($remainingText.Length -gt 0) {
        $currentChunk = $remainingText.Substring(0, [Math]::Min($remainingText.Length, $maxLength))
        $chunks += $currentChunk
        $remainingText = $remainingText.Substring([Math]::Min($remainingText.Length, $maxLength))
    }

    return $chunks
}

function Get-OpenAIResponse {
    param (
        [Parameter(Mandatory = $false)]
        [string]$system,
        
        # Prompt text
        [Parameter(Mandatory = $true)]
        [string]$prompt,
    
        # OpenAI API Key
        [Parameter(Mandatory = $false)]
        [string]$OPEN_AI_KEY = $env:OPENAI_API_KEY
    )

    Write-VerboseLog "==============Get-OpenAIResponse:START"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Write-VerboseLog "-----------------------------------------"

    # Estimate tokens for the prompt
    $tokenEstimate = Get-TokenEstimate $prompt
    $maxTokensPerChunk = 100000  # Leave room for model response

    # Split the prompt into chunks if it exceeds the max token size
    if ($tokenEstimate -gt $maxTokensPerChunk) {
        Write-Debug "Prompt exceeds max token size, chunking..."
        $chunks = Get-TextChunks -text $prompt -maxLength ($maxTokensPerChunk * 4)  # Approximate character length
    }
    else {
        $chunks = @($prompt)
    }

    # Initialize result
    $chunkResults = @()

    # Process each chunk
    foreach ($chunk in $chunks) {
        Write-Debug "Processing chunk..."
        $result = Call-OpenAI -system $system -prompt $chunk -OPEN_AI_KEY $OPEN_AI_KEY
        
        # Store the result of each chunk
        $chunkResults += $result
    }

    # Combine results if more than one chunk
    if ($chunkResults.Count -gt 1) {
        Write-Debug "Combining chunked responses..."
        $combinedPrompt = "Here are several responses from different parts of a git diff summarization task: `n`n" + ($chunkResults -join "`n") + "`n`nPlease combine these into a single, coherent summary."
        $fullResult = Call-OpenAI -system $system -prompt $combinedPrompt -OPEN_AI_KEY $OPEN_AI_KEY
    }
    else {
        $fullResult = $chunkResults[0]  # Only one chunk, no need to combine
    }

    Write-VerboseLog "-----------------------------------------"
    $sw.Stop()
    Write-VerboseLog "==============Get-OpenAIResponse:END | Elapsed time: $($sw.Elapsed)"
    
    return $fullResult
}

Write-InfoLog "OpenAI.ps1 loaded" 