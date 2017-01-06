<#
#>
Describe 'Common Tests - Azure Automation DSC' -Tag AADSCIntegration {

    $ResourceGroup = "TestAutomation$env:BuildID"
    $AutomationAccount = "DSCValidation$env:BuildID"

    $CurrentModuleManifest = Get-ChildItem -Path $env:BuildFolder -Filter "$env:ProjectName.psd1" | ForEach-Object {$_.FullName}
    $RequiredModules = Get-RequiredGalleryModules (Import-PowerShellDataFile $CurrentModuleManifest)
    $Configurations = Get-DSCConfigurationCommands

    # Get AADSC Modules
    $Modules = Get-AzureRmAutomationModule -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount

    # Get AADSC Configurations
    $Configurations = Get-AzureRmAutomationDscConfiguration -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccount

    Context "Modules" {
        It 'Modules should be present in AADSC account' {
            $Modules.count | Should Not BeNullorEmpty
        }
    }
    Context "Configurations" {
        It 'Configurations should be present in AADSC account' {
            $Configurations.count | Should Not BeNullorEmpty
        }
    }
}
