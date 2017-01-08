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
function Get-DSCConfigurationCommands {
param(
    [string]$Module
)
    $CommandParams = @{
        CommandType = 'Configuration'
        Module = $Module
    }
    Get-Command @CommandParams
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
function Invoke-ConfigurationPrep {
    param(
        [string]$Module = "*",
        [string]$Path = "$env:TEMP\DSCConfigurationScripts"
    )
    try {
        # Get list of configurations loaded from module
        $Configurations = Get-DSCConfigurationCommands -Module $Module
        $Configurations | Add-Member -MemberType NoteProperty -Name Location -Value $null
        $Configurations | Add-Member -MemberType NoteProperty -Name WindowsOSVersion -Value (Get-Module -Name $Module).PrivateData.PSData.WindowsOSVersion


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

<##>
function Invoke-AzureSPNLogin {
    param(
        [string]$ApplicationID,
        [string]$ApplicationPassword,
        [string]$TenantID
    )
    try {
        # Build platform (AppVeyor) does not offer solution for passing secure strings
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
function New-ResourceGroupandAutomationAccount {
    param(
        [string]$Location = 'EastUS2',
        [string]$ResourceGroupName = 'TestAutomation'+$env:BuildID,
        [string]$AutomationAccountName = 'DSCValidation'+$env:BuildID
    )
    try {
        # Create Resource Group
        $ResourceGroup = New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location -Force

        # Create Azure Automation account
        $AutomationAccount = New-AzureRMAutomationAccount -ResourceGroupName $ResourceGroupName -Name $AutomationAccountName -Location $Location

        if ($Account = Get-AzureRmAutomationAccount -ResourceGroupName $ResourceGroupName -Name $AutomationAccountName) {
            return $true
        }
        else {
            return $false
        }
    }
    catch [System.Exception] {
        throw "A failure occured while creating the Resource Group $ResourceGroupName or Automation Account $AutomationAccountName`n$error"
    }
}

<##>
function Remove-AzureTestResources {
    param(
        [string]$ResourceGroupName = 'TestAutomation'+$env:BuildID
    )
    try {
        $Remove = Remove-AzureRmResourceGroup -Name $ResourceGroupName -Force
    }
    catch [System.Exception] {
        throw "An error occured while removing the Resource Group $ResourceGroupName`n$error"
    }
}

<#
TODO should catch issues with import and return to build log
#>
function Import-ModuleToAzureAutomation {
    param(
        [array]$Module,
        [string]$ResourceGroupName = 'TestAutomation'+$env:BuildID,
        [string]$AutomationAccountName = 'DSCValidation'+$env:BuildID
    )
    try {
        # Import module from custom object
        $ImportedModule = New-AzureRMAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $Module.Name -ContentLink $Module.URI
    }
    catch [System.Exception] {
        throw "An error occured while importing the module $($Module.Name) to Azure Automation`n$error"
    }
}

<#
TODO need timeout based on real expectations
#>
function Wait-ModuleExtraction {
    param(
        [array]$Module,
        [string]$ResourceGroupName = 'TestAutomation'+$env:BuildID,
        [string]$AutomationAccountName = 'DSCValidation'+$env:BuildID
    )
    try {
        # The resource modules must finish the "Creating" stage before the configuration will compile successfully
        while ((Get-AzureRMAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $Module.Name).ProvisioningState -ne 'Succeeded') {
                Start-Sleep -Seconds 15
        }
    }
    catch [System.Exception] {
        throw "An error occured while waiting for module $($Module.Name) activities to extract in Azure Automation`n$error"        
    }
}    

<##>
function Import-ConfigurationToAzureAutomation {
    param(
        [psobject]$Configuration,
        [string]$ResourceGroupName = 'TestAutomation'+$env:BuildID,
        [string]$AutomationAccountName = 'DSCValidation'+$env:BuildID
    )
    try {
            # Import Configuration to Azure Automation DSC
            $ConfigurationImport = Import-AzureRmAutomationDscConfiguration -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -SourcePath $Configuration.Location -Published -Force

            # Load configdata if it exists
            if (Test-Path "$env:BuildFolder\ConfigurationData\$($Configuration.Name).ConfigData.psd1") {
                $ConfigurationData = Import-PowerShellDataFile ".\ConfigurationData\$($Configuration.Name).ConfigData.psd1"
            }

            # Splate params to compile in Azure Automation DSC
            $CompileParams = @{
            ResourceGroupName     = $ResourceGroupName
            AutomationAccountName = $AutomationAccountName
            ConfigurationName     = $Configuration.Name
            ConfigurationData     = $ConfigurationData
        }
        $Compile = Start-AzureRmAutomationDscCompilationJob @CompileParams
    }
    catch [System.Exception] {
        throw "An error occured while importing the configuration $($Configuration.Name) using Azure Automation`n$error"        
    }
}

<#
TODO need timeout based on real expectations
#>
function Wait-ConfigurationCompilation {
    param(
        [psobject]$Configuration,
        [string]$ResourceGroupName = 'TestAutomation'+$env:BuildID,
        [string]$AutomationAccountName = 'DSCValidation'+$env:BuildID
    )
    try {
        while ((Get-AzureRmAutomationDscCompilationJob -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $Configuration.Name).Status -ne 'Completed') {
            Start-Sleep -Seconds 15
        }   
    }
    catch [System.Exception] {
        throw "An error occured while waiting for configuration $($Configuration.Name) to compile in Azure Automation`n$error"        
    }
}

<##>
function New-AzureTestVM {
param(
    [string]$BuildID,
    [string]$Configuration,
    [string]$WindowsOSVersion
)
    Write-Output "Deploying build $BuildID of configuration $($Configuration.Name) to OS version $WindowsOSVersion"
    # Retrieve Azure Automation DSC registration information
    $Account = Get-AzureRMAutomationAccount -ResourceGroupName "TestAutomation$BuildID" `
    -Name "DSCValidation$BuildID"
    $RegistrationInfo = $Account | Get-AzureRmAutomationRegistrationInfo
    $registrationUrl = $RegistrationInfo.Endpoint
    $registrationKey = $RegistrationInfo.PrimaryKey | ConvertTo-SecureString -AsPlainText `
    -Force

    # Random password for local administrative account
    $adminPassword = new-randompassword -length 24 -UseSpecialCharacters | `
    ConvertTo-SecureString -AsPlainText -Force

    # DNS name based on random chars followed by first 10 of configuration name
    $dnsLabelPrefix = "$($Configuration.Name.substring(0,10).ToLower())$(Get-Random -Minimum 1000 -Maximum 9999)"

    # VM Name based on configuration name and OS name
    $vmName = "$($Configuration.Name).$($WindowsOSVersion.replace('-',''))"

    New-AzureRMResourceGroupDeployment -Name $BuildID `
    -ResourceGroupName "TestAutomation$BuildID" `
    -TemplateFile "$env:BuildFolder\DSCConfiguration.Tests\AzureDeploy.json" `
    -TemplateParameterFile "$env:BuildFolder\DSCConfiguration.Tests\AzureDeploy.parameters.json" `
    -dnsLabelPrefix $dnsLabelPrefix `
    -vmName $vmName `
    -WindowsOSVersion $WindowsOSVersion `
    -adminPassword $adminPassword `
    -registrationUrl $registrationUrl `
    -registrationKey $registrationKey `
    -nodeConfigurationName "$($Configuration.Name).localhost"

    $Status = Get-AzureRMResourceGroupDeployment -ResourceGroupName "TestAutomation$BuildID" `
    -Name $BuildID

    if ($Status.ProvisioningState -eq 'Succeeded') {
        Write-Output $Status.Outputs
    }
    else {
        $Error = Get-AzureRMDeploymentOperation -ResourceGroupName "TestAutomation$BuildID" `
        -Name $BuildID
        $Message = $Error.Properties | Where-Object {$_.ProvisioningState -eq 'Failed'} | `
        ForEach-Object {$_.StatusMessage} | ForEach-Object {$_.Error} | `
        ForEach-Object {$_.Details} | ForEach-Object {$_.Message}
        Write-Error $Message
    }
}

<#
    This work was originally published in the PowerShell xJEA module.
    https://github.com/PowerShell/xJea/blob/dev/DSCResources/Library/JeaAccount.psm1
    .Synopsis
    Creates a random password.
    .DESCRIPTION
    Creates a random password by generating a array of characters and passing it to Get-Random
    .EXAMPLE
    PS> New-RandomPassword
    g0dIDojsRGcV
    .EXAMPLE
    PS> New-RandomPassword -Length 3
    dyN
    .EXAMPLE
    PS> New-RandomPassword -Length 30 -UseSpecialCharacters
    r5Lhs1K9n*joZl$u^NDO&TkWvPCf2c
#>
function New-RandomPassword
{
    [CmdletBinding()]
    [OutputType([String])]
    Param
    (
        # Length of the password
        [Parameter(Mandatory=$False, Position=0)]
        [ValidateRange(12, 127)]
        $Length=12,

        # Includes the characters !@#$%^&*-+ in the password
        [switch]$UseSpecialCharacters
    )

    [char[]]$allowedCharacters = ([Char]'a'..[char]'z') + ([char]'A'..[char]'Z') + ([byte][char]'0'..[byte][char]'9')
    if ($UseSpecialCharacters)
    {
        foreach ($c in '!','@','#','$','%','^','&','*','-','+')
        {
            $allowedCharacters += [char]$c
        }
    }

    $characters = 1..$Length | ForEach-Object {
        $characterIndex = Get-Random -Minimum 0 -Maximum $allowedCharacters.Count
        $allowedCharacters[$characterIndex]
    }

    return (-join $characters)
}
