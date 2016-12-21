<#
#>
Describe 'Universal configuration tests' {
    $Name = Get-Item -Path $env:APPVEYOR_BUILD_FOLDER | ForEach-Object -Process {$_.Name}
    $Files = Get-ChildItem -Path $env:APPVEYOR_BUILD_FOLDER
    $Manifest = Import-PowerShellDataFile -Path "$env:APPVEYOR_BUILD_FOLDER\$Name.psd1"
    Context "$Name module manifest properties" {
        It 'Contains a module file that aligns to the folder name' {
            $Files.Name.Contains("$Name.psm1") | Should Be True
        }
        It 'Contains a module manifest that aligns to the folder and module names' {
            $Files.Name.Contains("$Name.psd1") | Should Be True
        }
        It 'Contains a readme' {
            $Files.Name.Contains("README.md") | Should Be True
        }
        It "Manifest $env:APPVEYOR_BUILD_FOLDER\$Name.psd1 should import as a data file" {
            $Manifest | Should Be 'System.Collections.Hashtable'
        }
        It 'Should point to the root module in the manifest' {
            $Manifest.RootModule | Should Be ".\$Name.psm1"
        }
        It 'Should have a GUID in the manifest' {
            $Manifest.GUID | Should Match '[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}'
        }
        It 'Should list requirements in the manifest' {
            $Manifest.RequiredModules | Should Not Be Null
        }
        It 'Should list a module version in the manifest' {
            $Manifest.ModuleVersion | Should BeGreaterThan 0.0.0.0
        }
        It 'Should list an author in the manifest' {
            $Manifest.Author | Should Not Be Null
        }
        It 'Should provide a description in the manifest' {
            $Manifest.Description | Should Not Be Null
        }
        It 'Should require PowerShell version 4 or later in the manifest' {
            $Manifest.PowerShellVersion | Should BeGreaterThan 4.0
        }
        It 'Should require CLR version 4 or later in the manifest' {
            $Manifest.CLRVersion | Should BeGreaterThan 4.0
        }
        It 'Should export functions in the manifest' {
            $Manifest.FunctionsToExport | Should Not Be Null
        }
        It 'Should include tags in the manifest' {
            $Manifest.PrivateData.PSData.Tags | Should Not Be Null
        }
        It 'Should include a project URI in the manifest' {
            $Manifest.PrivateData.PSData.ProjectURI | Should Not Be Null
        }
    }
    Context "$Name required modules" {
        ForEach ($RequiredModule in $Manifest.RequiredModules) {
            if ($RequiredModule.GetType().Name -eq 'Hashtable') {
                It "$($RequiredModule.ModuleName) version $($RequiredModule.ModuleVersion) should be found in the PowerShell public gallery" {
                    Find-Module -Name $RequiredModule.ModuleName -RequiredVersion $RequiredModule.ModuleVersion -ErrorAction SilentlyContinue | Should Not Be Null
                }
            }
            else {
                It "$RequiredModule should be found in the PowerShell public gallery" {
                    Find-Module -Name $RequiredModule -ErrorAction SilentlyContinue | Should Not Be Null
                }
            }
        }
    }
}

# requirements should be found in gallery

# requirements should install locally

# at least the requirements for each configuration should be listed in the manifest

# each configuration should compile locally

# each configuration should produce a mof

# after:
# technically are these unit or integration?

# modules should be in AADSC

# modules should show extracted activities

# configurations should be in AADSC

# configurations should show as compiled
