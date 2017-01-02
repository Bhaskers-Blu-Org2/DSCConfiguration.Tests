

<#
        TODO - Deploy
          $DeployParams = @{
            ResourceGroupName     = $env:APPVEYOR_BUILD_ID
            Name                  = $Configuration.Name
            TemplateFile          = '.\Tests\Deployment\azuredeploy.json'
            TemplateParameterFile = '.\Tests\Deployment\azuredeploy.parameters.json'
          }
        $IaaSDeployment = New-AzureRMResourceGroupDeployment @DeployParams
        #>
        
        

# after:
# technically are these unit or integration?

# modules should be in AADSC

# modules should show extracted activities

# configurations should be in AADSC

# configurations should show as compiled


        # TODO - standardize approach to deploying ARM template from repo handing off config name as param        
        # TODO - MVP is single VM, complete is multiple VM solution
        # TODO - tests from demo_ci
        