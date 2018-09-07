#region setup
$WorkingDir = $psISE.CurrentFile.FullPath | Split-Path
Set-Location $WorkingDir
#Add-AzureRmAccount
$AAAcct = Get-AzureRmAutomationAccount -Name DSCDemo01 -ResourceGroupName DSCDemo01

function Wait-AADSCCompileJob {
    param (
        [parameter(Mandatory,ValueFromPipeline)]
        [Microsoft.Azure.Commands.Automation.Model.CompilationJob] $CompileJob,

        [int] $Sleep = 2,

        [Switch] $PassThru
    )
    process {
        while ($null -eq $CompileJob.EndTime -and $null -eq $CompileJob.Exception) {
            $CompileJob = $CompileJob | Get-AzureRmAutomationDscCompilationJob
            Start-Sleep -Seconds $Sleep
        }
        if ($PassThru) {
            Write-Output -InputObject $CompileJob
        }
    }
}

#endregion

#region Configuration with Parameters
<# ConfigWithParams.ps1
configuration ConfigWithParams {
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $FirstName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $LastName,

        [int] $Age,

        [bool] $OverWrite = $false
    )
    Import-DscResource -ModuleName PSDesiredStateConfiguration -ModuleVersion 1.1

    file WriteNameToFile {
        Ensure = 'Present'
        DestinationPath = 'c:\MyName.txt'
        Type = 'File'
        Contents = "$FirstName,$LastName,$Age"
        Force = $OverWrite
    }
}
#>
psEdit $WorkingDir\ConfigWithParams.ps1
$ImportParams1 = $AAAcct | Import-AzureRmAutomationDscConfiguration -SourcePath $WorkingDir\ConfigWithParams.ps1 `
                                                                    -Published

$Params1 = @{
    FirstName = 'Ben'
    LastName = 'Gelens'
    Age = 21
    OverWrite = $true
}

$Params1CompileJob = $ImportParams1 | Start-AzureRmAutomationDscCompilationJob -Parameters $Params1
$Params1CompileJob = $Params1CompileJob | Wait-AADSCCompileJob -PassThru
$Params1CompileJob
$Params1CompileJob.JobParameters
$Params1CompileJob | Get-AzureRmAutomationDscCompilationJobOutput
#endregion

#region Configuration with sensitive data
<# ConfigWithCredParams.ps1
configuration ConfigWithCredParams {
    param (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $UserName,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $Password
    )
    Import-DscResource -ModuleName PSDesiredStateConfiguration -ModuleVersion 1.1
    node localhost {
        
        $Cred = [pscredential]::new($UserName,(ConvertTo-SecureString -String $Password -AsPlainText -Force))

        user NewUser {
            UserName = $UserName
            Password = $Cred
            Ensure = 'Present'
            FullName = $UserName
        }
    }
}
#>
psEdit $WorkingDir\ConfigWithCredParams.ps1

$ImportParams2 = $AAAcct | Import-AzureRmAutomationDscConfiguration -SourcePath $WorkingDir\ConfigWithCredParams.ps1 `
                                                                    -Published

$Params2 = @{
    Username = 'Ben'
    Password = 'Welcome01'
}
$Params2CompileJob = $ImportParams2 | Start-AzureRmAutomationDscCompilationJob -Parameters $Params2
$Params2CompileJob = $Params2CompileJob | Wait-AADSCCompileJob -PassThru
$Params2CompileJob

$ConfigData1 = @{
    AllNodes = @(
        @{
            NodeName = 'Localhost'
            PsDscAllowPlainTextPassword = $true
        }
    )
}
$Params2CompileJob = $ImportParams2 | Start-AzureRmAutomationDscCompilationJob -Parameters $Params2 -ConfigurationData $ConfigData1
$Params2CompileJob = $Params2CompileJob | Wait-AADSCCompileJob -PassThru
$Params2CompileJob
#endregion

#region Configuration using AA Asset via Param
<# ConfigWithPSCredParams.ps1
configuration ConfigWithPSCredParams {
    param (
        [Parameter(Mandatory)]
        [PSCredential] $Credential
    )
    node localhost {
        user NewUser {
            UserName = $Credential.UserName
            Password = $Credential
            Ensure = 'Present'
            FullName = $Credential.UserName
        }
    }
}
#>
psEdit $WorkingDir\ConfigWithPSCredParams.ps1

$ImportParams3 = $AAAcct | Import-AzureRmAutomationDscConfiguration -SourcePath $WorkingDir\ConfigWithPSCredParams.ps1 `
                                                                    -Published

$Params3 = @{
    Credential = [pscredential]::new('ben',(ConvertTo-SecureString -String 'Welcome01' -AsPlainText -Force))
}
$Params3CompileJob = $ImportParams3 | Start-AzureRmAutomationDscCompilationJob -Parameters $Params3 -ConfigurationData $ConfigData1
$Params3CompileJob = $Params3CompileJob | Wait-AADSCCompileJob -PassThru
$Params3CompileJob
$Params3CompileJob.JobParameters

$AAAcct | New-AzureRmAutomationCredential -Name MyCreds -Value $params3.Credential

$Params3 = @{
    Credential = 'MyCreds'
}
$Params3CompileJob = $ImportParams3 | Start-AzureRmAutomationDscCompilationJob -Parameters $Params3 -ConfigurationData $ConfigData1
$Params3CompileJob = $Params3CompileJob | Wait-AADSCCompileJob -PassThru
$Params3CompileJob
$Params3CompileJob.JobParameters
#endregion

#region Configuration using AA Assets
<# ConfigWithAAAssets.ps1
configuration ConfigWithAAAssets {
    Import-DscResource -ModuleName PSDesiredStateConfiguration -ModuleVersion 1.1
    node localhost {
        
        $Cred = Get-AutomationPSCredential -Name MyCreds
        $UserName = Get-AutomationVariable -Name MyUserName

        user NewUser {
            UserName = $UserName
            Password = $Cred
            Ensure = 'Present'
            FullName = $UserName
        }
    }
}
#>
psEdit $WorkingDir\ConfigWithAAAssets.ps1
$AAAcct | New-AzureRmAutomationVariable -Name MyUserName -Value 'Ben' -Encrypted $false

$ImportAssets = $AAAcct | Import-AzureRmAutomationDscConfiguration -SourcePath $WorkingDir\ConfigWithAAAssets.ps1 `
                                                                   -Published

$AssetsCompileJob = $ImportAssets | Start-AzureRmAutomationDscCompilationJob -ConfigurationData $ConfigData1
$AssetsCompileJob = $AssetsCompileJob | Wait-AADSCCompileJob -PassThru
$AssetsCompileJob
#endregion

#region non-inbox DSC Resource
$NX = Find-Module -Name NX
$NX | Save-Module -Path $WorkingDir
Compress-Archive -Path $WorkingDir\NX -DestinationPath $WorkingDir\NX.zip
$StorageAcct = New-AzureRmStorageAccount -ResourceGroupName $AAAcct.ResourceGroupName -Name dscmodules -Type Standard_LRS -Location westeurope
$null = $StorageAcct | New-AzureStorageContainer -Name dscmodules -Permission Container
$ModuleUpload = Set-AzureStorageBlobContent -Context $StorageAcct.Context -Container dscmodules -File $WorkingDir\NX.zip
$ModuleUpload.ICloudBlob.StorageUri.PrimaryUri.OriginalString
$Upload = $AAAcct | New-AzureRmAutomationModule -Name NX -ContentLink $ModuleUpload.ICloudBlob.StorageUri.PrimaryUri.OriginalString

while ($Upload.ProvisioningState -ne 'Succeeded' -and $Upload.ProvisioningState -ne 'Failed') {
    $Upload = $Upload | Get-AzureRmAutomationModule
    $Upload.ProvisioningState
    Start-Sleep -Seconds 10
}
$Upload | Get-AzureRmAutomationModule

#show portal experience
#endregion

#region configuration non inbox resource
<# NginX.ps1
Configuration NginX {
    param (
        [String] $HTMLData = '<center><H1>Hello World!</H1></center>'
    )
    Import-DSCResource -Module NX

    node 'FrontEnd' {
        nxPackage EPEL {
            Ensure = 'Present'
            Name = 'epel-release'
            PackageManager = 'Yum'
        }

        nxPackage NginX {
            Ensure = 'Present'
            Name = 'nginx'
            PackageManager = 'Yum'
            DependsOn = '[nxPackage]EPEL'
        }

        nxFile MyCoolWebPage {
            DestinationPath = '/usr/share/nginx/html/index.html'
            Contents = $HTMLData
            Force = $true
            DependsOn = '[nxPackage]NginX'
        }
        
        nxService NginXService {
            Name = 'nginx'
            Controller = 'systemd'
            Enabled = $true
            State = 'Running'
            DependsOn = '[nxFile]MyCoolWebPage'
        }
    }
}
#>
psEdit $WorkingDir\NginX.ps1

$WebSite = '<center><H1>Hello World! This Linux node is configured via Azure Automation DSC :-)</H1></center>
<center><img src="https://msdnshared.blob.core.windows.net/media/TNBlogsFS/prod.evol.blogs.technet.com/CommunityServer.Blogs.Components.WeblogFiles/00/00/00/41/57/ms_loves_linux.png"></center>'


$ImportNginX = $AAAcct | Import-AzureRmAutomationDscConfiguration -SourcePath $WorkingDir\NginX.ps1 `
                                                                  -Published

$NginXCompileJob = $ImportNginX | Start-AzureRmAutomationDscCompilationJob -Parameters @{HTMLData = $WebSite}
$NginXCompileJob = $NginXCompileJob | Wait-AADSCCompileJob -PassThru
$NginXCompileJob
#endregion

#region assign Linux Configuration
$VM = Get-AzureRmVM -ResourceGroupName DSCNodes -Name DSCNode3
$IPAddress = ($VM | Get-AzureRmPublicIpAddress).IpAddress
<#
    Start-Process ssh ben@$IPAddress
    sudo su -
    passwd root
    passwd -u root

#>
$CimSessionOption = New-CimSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck -UseSsl
$CimSession = New-CimSession -ComputerName $IPAddress `
                             -SessionOption $CimSessionOption `
                             -Credential ([pscredential]::new('root',(ConvertTo-SecureString -String 'root' -AsPlainText -Force))) `
                             -Authentication Basic

Update-DscConfiguration -CimSession $CimSession -Wait -Verbose
Start-Process microsoft-edge:http://$IPAddress
Get-DscConfiguration -CimSession $CimSession
#endregion

#region import precompiled
<# Telnet.ps1
configuration Telnet {
    WindowsFeature 'TelNet' {
        Name = 'Telnet-Client'
        Ensure = 'Present'
    }
}
#>
psEdit $WorkingDir\Telnet.ps1
. $WorkingDir\Telnet.ps1
Telnet -Output $WorkingDir
$AAAcct | Import-AzureRmAutomationDscNodeConfiguration -Path $WorkingDir\localhost.mof -ConfigurationName Telnet
#endregion