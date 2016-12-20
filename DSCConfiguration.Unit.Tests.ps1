<#
#>
Describe 'Universal configuration tests' {
    $Name = Get-Item -Path $env:APPVEYOR_BUILD_FOLDER | ForEach-Object -Process {$_.Name}
    $Files = Get-ChildItem -Path $env:APPVEYOR_BUILD_FOLDER
    $Manifest = Import-PowerShellDataFile -Path "$env:APPVEYOR_BUILD_FOLDER\$Name.psd1"
    Context "$Name Module properties" {
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
        It 'Should give a module version in the manifest' {
            $Manifest.ModuleVersion | Should BeGreaterThan 0.0.0.0
        }
    }
}

# manifest should have name, id, root mod

# requirements should be found in gallery

# requirements should install locally

# each configuration should compile locally

# each configuration should produce a mof

# after:
# technically are these unit or integration?

# modules should be in AADSC

# modules should show extracted activities

# configurations should be in AADSC

# configurations should show as compiled
