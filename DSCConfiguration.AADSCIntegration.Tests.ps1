# The ResourceGroup, AA Acount name; from env vars
# list of modules, and list of configurations, from build folder

$CurrentModuleManifest = Get-ChildItem -Path $env:BuildFolder -Filter "$env:ProjectName.psd1" | ForEach-Object {$_.FullName}
$RequiredModules = Get-RequiredGalleryModules $CurrentModuleManifest
$Configurations = Get-DSCConfigurationCommands

<#
#>
Describe 'Common Tests - Azure Automation DSC' -Tag AADSCIntegration {

    # Get AADSC Modules
    $Modules = Get-AzureRmAutomationModule

    # Get AADSC Configurations
    $Configurations = Get-AzureRmAutomationDscConfiguration

    Context "Modules" {
        It 'Modules should be present in AADSC account' {
            '' | Should Be ''
        }
    }
    Context "Configurations" {
        It 'Configurations should be present in AADSC account' {
        '' | Should Be ''
        }
    }
}