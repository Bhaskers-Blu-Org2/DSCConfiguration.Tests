<#
Comments
#>

$env:ResourceGroupName = 'TestAutomation'+$env:APPVEYOR_BUILD_ID
$env:AutomationAccountName = 'DSCValidation'+$env:APPVEYOR_BUILD_ID

<##>
function New-ResourceGroupforTests {
    param(
        [string]$Location = 'EastUS2',
        [string]$ResourceGroupName = $env:ResourceGroupName,
        [string]$AutomationAccountName = $env:AutomationAccountName
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
        [string]$ResourceGroupName = $env:ResourceGroupName
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
        [string]$ResourceGroupName = $env:ResourceGroupName,
        [string]$AutomationAccountName = $env:AutomationAccountName
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
        [string]$ResourceGroupName = $env:ResourceGroupName,
        [string]$AutomationAccountName = $env:AutomationAccountName
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
        [string]$ResourceGroupName = $env:ResourceGroupName,
        [string]$AutomationAccountName = $env:AutomationAccountName
    )
    try {
            # Import Configuration to Azure Automation DSC
            $ConfigurationImport = Import-AzureRmAutomationDscConfiguration -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -SourcePath $Configuration.Location -Published -Force

            # Load configdata if it exists
            if (Test-Path ".\ConfigurationData\$($Configuration.Name).ConfigData.psd1") {
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
        [string]$ResourceGroupName = $env:ResourceGroupName,
        [string]$AutomationAccountName = $env:AutomationAccountName
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
