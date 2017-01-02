<#
Comments
#>

<##>
function Invoke-UniquePSModulePath {
    try {
        # Correct duplicates in environment psmodulepath
        foreach($path in $env:psmodulepath.split(';').ToUpper().ToLower()) {
            [array]$correctDirFormat += "$path\;"
        }
        $correctDirFormat = $correctDirFormat.replace("\\","\") | Where-Object {$_ -ne '\;'} | Select-Object -Unique
        foreach ($path in $correctDirFormat.split(';')) {
            [string]$fixPath += "$path;"
        }
        $env:psmodulepath = $fixpath.replace(';;',';')
    }
    catch [System.Exception] {
        throw "An error occured while correcting the psmodulepath`n$error"
    }
}

<##>
function Get-RequiredGalleryModules {
    param(
        [hashtable]$ManifestData,
        [switch]$Install
    )
    try {
        # Load module data and create array of objects containing prerequisite details for use later in Azure Automation
        $ModulesInformation = @()
        foreach($RequiredModule in $ManifestData.RequiredModules[0])
        {
            # Placeholder object to store module names and locations
            $ModuleReference = New-Object -TypeName PSObject
            
            # If no version is given, get the latest version
            if ($RequiredModule.gettype().Name -eq 'String')
            {
                if ($galleryReference = Invoke-RestMethod -Method Get -Uri "https://www.powershellgallery.com/api/v2/FindPackagesById()?id='$RequiredModule'" -ErrorAction Continue)
                {
                $ModuleReference | Add-Member -MemberType NoteProperty -Name 'Name' -Value $RequiredModule
                $ModuleReference | Add-Member -MemberType NoteProperty -Name 'URI' -Value ($galleryReference | Where-Object {$_.Properties.IsLatestVersion.'#text' -eq $true}).content.src
                $ModulesInformation += $ModuleReference
                }
                if ($Install -eq $true)
                {
                    Install-Module -Name $RequiredModule -force
                }
            }

            # If a version is given, get it specifically
            if ($RequiredModule.gettype().Name -eq 'Hashtable')
            {
                if ($galleryReference = Invoke-RestMethod -Method Get -Uri "https://www.powershellgallery.com/api/v2/FindPackagesById()?id='$($RequiredModule.ModuleName)'" -ErrorAction Continue)
                {
                $ModuleReference | Add-Member -MemberType NoteProperty -Name 'Name' -Value $RequiredModule.ModuleName
                $ModuleReference | Add-Member -MemberType NoteProperty -Name 'URI' -Value ($galleryReference | Where-Object {$_.Properties.Version -eq $RequiredModule.ModuleVersion}).content.src
                $ModulesInformation += $ModuleReference
                }
                if ($Install -eq $true)
                {
                    Install-Module -Name $RequiredModule.ModuleName -RequiredVersion $RequiredModule.ModuleVersion -force
                }
            }
        }
        return $ModulesInformation    
    }
    catch [System.Exception] {
        throw "An error occured while getting modules from PowerShellGallery.com`n$error"
    }
}

<##>
function Invoke-AzureSPNLogin {
    param(
        [string]$ApplicationID,
        [string]$ApplicationPassword,
        [string]$TenantID
    )
    try {
        # TODO - is there a better way to pass secure strings from AppVeyor
        $Credential = New-Object -typename System.Management.Automation.PSCredential -argumentlist $ApplicationID, $(convertto-securestring -String $ApplicationPassword -AsPlainText -Force)
    
        # Suppress request to share usage information
        $Path = "$Home\AppData\Roaming\Windows Azure Powershell\"
        if (!(Test-Path -Path $Path)) {
            $AzPSProfile = New-Item -Path $Path -ItemType Directory
        }
        $AzProfileContent = Set-Content -Value '{"enableAzureDataCollection":true}' -Path (Join-Path $Path 'AzureDataCollectionProfile.json') 

        # Handle Login
        if (Add-AzureRmAccount -Credential $Credential -ServicePrincipal -TenantID $TenantID -ErrorAction SilentlyContinue) {
            return $true
        }
        else {
            return $false
        }
    }
    catch [System.Exception] {
        throw "An error occured while logging in to Azure`n$error"    
    }
}

<##>
function Invoke-ConfigurationPrep {
    param(
        [string]$Module = "*",
        [string]$Path = "$env:TEMP\DSCConfigurationScripts"
    )
    try {
        # Get list of configurations loaded from module
        $Configurations = Get-Command -Type 'Configuration' -Module $Module
        $Configurations | Add-Member -MemberType NoteProperty -Name Location -Value $null

        # Create working folder
        New-Item -Path $Path -ItemType Directory -Force | Out-Null
    
        # Create a unique script for each configuration, with a name that matches the configuration
        foreach ($Configuration in $Configurations) {
            if ($Config = (Get-Command $Configuration).ScriptBlock) {
                $Configuration.Location = "$Path\$Configuration.ps1"
                "Configuration $Configuration`n{" | Out-File $Configuration.Location
                $Config | Out-File $Configuration.Location -Append
                "}`n" | Out-File $Configuration.Location -Append
            }
        }

        return $Configurations
    }
    catch [System.Exception] {
        throw "An error occured while preparing configurations for import`n$error"
    }
}

<##>
function Import-ModuleFromSource {
    param(
        [string]$Name
    )
    try {
        if ($ModuleDir = New-Item -Type Directory -Path $env:ProgramFiles\WindowsPowerShell\Modules\$Name -force) {
            Copy-Item -Path .\$Name.psd1 -Destination $ModuleDir -force
            Copy-Item -Path .\$Name.psm1 -Destination $ModuleDir -force
            Import-Module -Name $Name
        }
    }
    catch [System.Exception] {
        throw "An error occured while importing module $Name`n$error"
    }
}

<#
    .SYNOPSIS
        Retrieves the parse errors for the given file.

    .PARAMETER FilePath
        The path to the file to get parse errors for.
#>
function Get-FileParseErrors
{
    [OutputType([System.Management.Automation.Language.ParseError[]])]
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [String]
        $FilePath
    )

    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref] $null, [ref] $parseErrors)

    return $parseErrors
}

<#
    .SYNOPSIS
        Retrieves all text files under the given root file path.

    .PARAMETER Root
        The root file path under which to retrieve all text files.

    .NOTES
        Retrieves all files with the '.gitignore', '.gitattributes', '.ps1', '.psm1', '.psd1',
        '.json', '.xml', '.cmd', or '.mof' file extensions.
#>
function Get-TextFilesList
{
    [OutputType([System.IO.FileInfo[]])]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $FilePath
    )

    $textFileExtensions = @('.gitignore', '.gitattributes', '.ps1', '.psm1', '.psd1', '.json', '.xml', '.cmd', '.mof')

    return Get-ChildItem -Path $FilePath -File -Recurse | Where-Object { $textFileExtensions -contains $_.Extension }
}

<#
    .SYNOPSIS
        Retrieves all .psm1 files under the given file path.

    .PARAMETER FilePath
        The root file path to gather the .psm1 files from.
#>
function Get-Psm1FileList
{
    [OutputType([Object[]])]
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [String]
        $FilePath
    )

    return Get-ChildItem -Path $FilePath -Filter '*.psm1' -File -Recurse
}

<#
    .SYNOPSIS
        Retrieves the list of suppressed PSSA rules in the file at the given path.

    .PARAMETER FilePath
        The path to the file to retrieve the suppressed rules of.
#>
function Get-SuppressedPSSARuleNameList
{
    [OutputType([String[]])]
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [String]
        $FilePath
    )

    $suppressedPSSARuleNames = [String[]]@()

    $fileAst = [System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref]$null, [ref]$null)

    # Overall file attrbutes
    $attributeAsts = $fileAst.FindAll({$args[0] -is [System.Management.Automation.Language.AttributeAst]}, $true)

    foreach ($attributeAst in $attributeAsts)
    {
        if ([System.Diagnostics.CodeAnalysis.SuppressMessageAttribute].FullName.ToLower().Contains($attributeAst.TypeName.FullName.ToLower()))
        {
            $suppressedPSSARuleNames += $attributeAst.PositionalArguments.Extent.Text
        }
    }

    return $suppressedPSSARuleNames
}

<#
    .SYNOPSIS
        Tests if a file is encoded in Unicode.

    .PARAMETER FileInfo
        The file to test.
#>
function Test-FileInUnicode
{
    [OutputType([Boolean])]
    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline = $true, Mandatory = $true)]
        [System.IO.FileInfo]
        $FileInfo
    )

    $filePath = $FileInfo.FullName
    $fileBytes = [System.IO.File]::ReadAllBytes($filePath)
    $zeroBytes = @( $fileBytes -eq 0 )

    return ($zeroBytes.Length -ne 0)
}
