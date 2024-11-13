$basePath = "site\content\resources\videos\youtube"

# Loop through each folder in the base path that matches "_2ZH7vbKu7Y"
$youtubeFolders = Get-ChildItem -Path $basePath -Directory | Select-Object -First 10
#$youtubeFolders = $youtubeFolders | Where-Object { $_.Name -match "_2ZH7vbKu7Y" }

$youtubeFolders | ForEach-Object {
    $youtubeId = $_.Name
    $mainFilePath = Join-Path -Path $_.FullName -ChildPath "index.md"
    $customFilePattern = Join-Path -Path $_.FullName -ChildPath "wordpress.custom*.md"
    $wprssFilePattern = Join-Path -Path $_.FullName -ChildPath "wordpress.wprss*.md"

    $frontMatter = [ordered]@{}
    $body = $null
    # Load the main file content
    if (Test-Path $mainFilePath) {
        $mainContent = Get-Content -Path $mainFilePath -Raw

        # Extract front matter and body from the main file
        if ($mainContent -match "(?s)^---(.*?)---\s*(.*)") {
            $frontMatter = ConvertFrom-Yaml $matches[1] -Ordered
            $body = $matches[2]
        }

        # Remove YouTube shortcode from body
        $body = $body -replace "{{< youtube [-_a-zA-Z0-9]+ >}}", ""

        # Add URL from main front matter to aliases if it exists
        if ($frontMatter.url -and $frontMatter.url -ne "/resources/videos/:slug") {
            if (-not $frontMatter.Contains('aliases')) {
                $frontMatter.aliases = @()
            }
            if (-not ($frontMatter.aliases -contains $frontMatter.url)) {
                $frontMatter.aliases += "$($frontMatter.url)"
            }
        }

        # ensure slug

        # Load front matter and body for custom files if they exist, using the newest date
        $customFiles = Get-ChildItem -Path $customFilePattern | Sort-Object { 
            $customContent = Get-Content -Path $_.FullName -Raw
            if ($customContent -match "(?s)^---(.*?)---") {
                $customFrontMatter = ConvertFrom-Yaml $matches[1] -Ordered
                [datetime]$customFrontMatter.date
            }
            else {
                [datetime]::MinValue
            }
        } -Descending

        foreach ($customFile in $customFiles) {
            $customFrontMatter = [ordered]@{}
            $customBody = ""
            $customContent = Get-Content -Path $customFile.FullName -Raw
            if ($customContent -match "(?s)^---(.*?)---\s*(.*)") {
                $customFrontMatter = ConvertFrom-Yaml $matches[1] -Ordered
                $customBody = $matches[2]
                
                # Remove the first instance of a YouTube URL from the custom body
                $youtubeUrlPattern = "https:\/\/youtube\.com\/shorts\/[a-zA-Z0-9_-]+|https:\/\/youtu\.be\/[a-zA-Z0-9_-]+"
                $customBody = $customBody -replace $youtubeUrlPattern, ""
                
                # Always use the body from the newest wordpress.custom*.md file
                $body = $customBody
                # Remove canonicalUrl from the front matter if wordpress.custom.md exists
                if ($frontMatter.Contains('canonicalUrl')) {
                    $frontMatter.Remove('canonicalUrl')
                }
                $frontMatter.title = $customFrontMatter.title
                $frontMatter.date = $customFrontMatter.date
                $frontMatter.url = "/resources/videos/:slug"
                
                # Add slug from customFrontMatter to aliases in main front matter
                if ($customFrontMatter.slug) {
                    if (-not $frontMatter.Contains('aliases')) {
                        $frontMatter.aliases = @()
                    }
                    if (-not ($frontMatter.aliases -contains "/resources/$($customFrontMatter.slug)")) {
                        $frontMatter.aliases += "/resources/$($customFrontMatter.slug)"
                    }
                }
                # Update URL to be all lowercase and replace special characters with "-"
                $sanitizedTitle = $customFrontMatter.title -replace "[^a-zA-Z0-9]+", "-" -replace "(^-+|-+$)", ""
                
                # Insert slug after URL if it does not exist
                if (-not $frontMatter.Contains('slug')) {
                    $frontMatter.Insert(($frontMatter.Keys.IndexOf('url') + 1), 'slug', $($sanitizedTitle.ToLower()))
                }
            }
        }

        # Iterate through all matching wordpress.wprss*.md files
        $wprssFiles = Get-ChildItem -Path $wprssFilePattern
        foreach ($wprssFile in $wprssFiles) {
            $wprssFrontMatter = [ordered]@{}
            $wprssBody = ""
            if (Test-Path $wprssFile.FullName) {
                $wprssContent = Get-Content -Path $wprssFile.FullName -Raw
                if ($wprssContent -match "(?s)^---(.*?)---\s*(.*)") {
                    $wprssFrontMatter = ConvertFrom-Yaml $matches[1] -Ordered
                    $wprssBody = $matches[2]

                    # Add slug from wprssFrontMatter to aliases in main front matter
                    if ($wprssFrontMatter.slug) {
                        if (-not $frontMatter.Contains('aliases')) {
                            $frontMatter.aliases = @()
                        }
                        if (-not ($frontMatter.aliases -contains "/resources/$($wprssFrontMatter.slug)")) {
                            $frontMatter.aliases += "/resources/$($wprssFrontMatter.slug)"
                        }
                    }
                }
            }
        }

        # Combine the contents
        $mergedContent = "---`n$($frontMatter | ConvertTo-Yaml)`n---`n`n{{< youtube $youtubeId >}}`n`n$body`n`n"

        # Write the merged content back to index.md
        Set-Content -Path $mainFilePath -Value $mergedContent

        Write-Output "Merged content updated for $youtubeId"
    }
    else {
        Write-Output "index.md not found for $youtubeId"
    }
}

Write-Output "All folders processed."
