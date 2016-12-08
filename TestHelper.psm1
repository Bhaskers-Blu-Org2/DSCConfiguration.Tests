<#
Comments
#>

<##>
function Invoke-UniquePSModulePath {
    # Correct duplicates in environment psmodulepath
    foreach($path in $env:psmodulepath.split(';').ToUpper().ToLower())
    {
        [array]$correctDirFormat += "$path\;"
    }
    $correctDirFormat = $correctDirFormat.replace("\\","\") | ? {$_ -ne '\;'} | Select-Object -Unique
    foreach ($path in $correctDirFormat.split(';'))
    {
        [string]$fixPath += "$path;"
    }
    $env:psmodulepath = $fixpath.replace(';;',';')
}

<##>
function Get-RequiredGalleryModules {
    param(
        [hashtable]$ManifestData,
        [switch]$Install
    )

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
            $ModuleReference | Add-Member -MemberType NoteProperty -Name 'URI' -Value ($galleryReference | ? {$_.Properties.IsLatestVersion.'#text' -eq $true}).content.src
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
            $ModuleReference | Add-Member -MemberType NoteProperty -Name 'URI' -Value ($galleryReference | ? {$_.Properties.Version -eq $RequiredModule.ModuleVersion}).content.src
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

<##>
function Invoke-AzureSPNLogin {
    param(
        [string]$ApplicationID = $env:ApplicationID,
        [string]$ApplicationPassword = $env:ApplicationPassword,
        [string]$TenantID = $env:TenantID
    )
    # TODO - is there a better way to pass secure strings from AppVeyor
    $Credential = New-Object -typename System.Management.Automation.PSCredential -argumentlist $ApplicationID, $(convertto-securestring -String $ApplicationPassword -AsPlainText -Force)
    
    # Suppress request to share usage information
    $Path = "$Home\AppData\Roaming\Windows Azure Powershell\"
    if (!(Test-Path -Path $Path))
    {
        $AzPSProfile = New-Item -Path $Path -ItemType Directory
    }
    $AzProfileContent = Set-Content -Value '{"enableAzureDataCollection":true}' -Path (Join-Path $Path 'AzureDataCollectionProfile.json') 

    # Handle Login
    if (Add-AzureRmAccount -Credential $Credential -ServicePrincipal -TenantId $TenantId -ErrorAction SilentlyContinue)
    {
        return $true
    }
    else 
    {
        return $false
    }
}

<##>
function Invoke-ConfigurationPrep {
    param(
        [string]$Module = "*",
        [string]$Path = "$env:TEMP\DSCConfigurationScripts"
    )
    
    # Get list of configurations loaded from module
    $Configurations = Get-Command -Type 'Configuration' -Module $Module
    $Configurations | Add-Member -MemberType NoteProperty -Name Location -Value $null

    # Create working folder
    New-Item -Path $Path -ItemType Directory -Force | Out-Null
    
    # Create a unique script for each configuration, with a name that matches the configuration
    foreach ($Configuration in ($Configurations | ForEach-Object -Process {$_.Name}))
    {
        if ($Config = (Get-Command $confName).ScriptBlock)
        {
            $Configuration.Location = "$Path\$confName.ps1"
            "Configuration $confName`n{" | Out-File $Configuration.Location
            $Config | Out-File $Configuration.Location -Append
            "}`n" | Out-File $Configuration.Location -Append
        }
    }

    return $Configurations
}

<##>
function Import-ModuleFromSource {
    param(
        [string]$Name
    )
    if ($ModuleDir = New-Item -Type Directory -Path $env:ProgramFiles\WindowsPowerShell\Modules\$Name -force)
    {
        Copy-Item -Path .\$Name.psd1 -Destination $ModuleDir -force
        Copy-Item -Path .\$Name.psm1 -Destination $ModuleDir -force
        Import-Module -Name $Name
    }
}
