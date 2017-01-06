<#
#>
Describe 'Common Tests - Azure Automation DSC' -Tag AADSCIntegration {

    $ResourceGroup = "TestAutomation$env:BuildID"
    $AutomationAccount = "DSCValidation$env:BuildID"

    $CurrentModuleManifest = Get-ChildItem -Path $env:BuildFolder -Filter "$env:ProjectName.psd1" | ForEach-Object {$_.FullName}
    $RequiredModules = Get-RequiredGalleryModules (Import-PowerShellDataFile $CurrentModuleManifest)
    $ConfigurationCommands = Get-DSCConfigurationCommands -Module $env:ProjectName

    # Get AADSC Modules
    $AADSCModules = Get-AzureRmAutomationModule -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount
    $AADSCModuleNames = $AADSCModules | ForEach-Object {$_.Name}

    # Get AADSC Configurations
    $AADSCConfigurations = Get-AzureRmAutomationDscConfiguration -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount
    $AADSCConfigurationNames = $AADSCCOnfigurations | ForEach-Object {$_.Name}

    Context "Modules" {
        ForEach ($RequiredModule in $RequiredModules) {
            It "$($RequiredModule.Name) should be present in AADSC" {
                $AADSCModuleNames.Contains("$RequiredModule") | Should Be True
            }
        }
    }
    Context "Configurations" {
        ForEach ($ConfigurationCommand in $ConfigurationCommands) {
            It "$ConfigurationCommand should be present in AADSC" {
                $AADSCConfigurationNames.Contains("$ConfigurationCommand") | Should Be True
            }
        }
    }
}
