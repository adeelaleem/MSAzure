#region setup
$WorkingDir = $psISE.CurrentFile.FullPath | Split-Path
Set-Location $WorkingDir
Add-AzureRmAccount
$AAAcct = Get-AzureRmAutomationAccount -Name DSCDemo01 -ResourceGroupName DSCDemo01
#endregion

#region list local VMs
Get-VM | Where-Object -FilterScript {$_.State -eq 'Running'}
#endregion

#region acquire prebaked meta.mof
$AAAcct | Get-AzureRmAutomationDscOnboardingMetaconfig -OutputFolder $WorkingDir
psedit $WorkingDir\DSCMetaConfigs\localhost.meta.mof
#endregion

#region create own meta.mof
$Keys = $AAAcct | Get-AzureRmAutomationRegistrationInfo
[DscLocalConfigurationManager()]
configuration LCM {
    param (
        [Parameter(Mandatory,ValueFromPipeline)]
        $Keys
    )
    Settings {
        ConfigurationMode = 'ApplyAndAutoCorrect'
        RefreshMode = 'Pull'
        RefreshFrequencyMins = 30
        RebootNodeIfNeeded = $true
        ActionAfterReboot = 'ContinueConfiguration'
        ConfigurationModeFrequencyMins = 15
    }
    ConfigurationRepositoryWeb AADSC {
        ServerURL = $Keys.Endpoint
        RegistrationKey = $Keys.PrimaryKey
    }
    ResourceRepositoryWeb AADSC {
        ServerURL = $Keys.Endpoint
        RegistrationKey = $Keys.PrimaryKey
    }
    ReportServerWeb AADSC {
        ServerURL = $Keys.Endpoint
        RegistrationKey = $Keys.PrimaryKey
    }
}
$Keys | LCM -OutputPath $WorkingDir
psEdit $WorkingDir\localhost.meta.mof
#endregion

#region onboard Windows 2012R2 with WMF5 RTM
$PsSessionArgs = @{
    ComputerName = '172.16.0.9'
    Credential = ([pscredential]::new('administrator',(ConvertTo-SecureString -String 'Welkom01' -AsPlainText -Force)))
}
$PSSession = New-PSSession @PsSessionArgs
Copy-Item $WorkingDir\DscMetaConfigs\localhost.meta.mof -ToSession $PSSession -Destination C:\
$PSSession | Enter-PSSession
Set-Location -Path c:\
Get-DscLocalConfigurationManager
Set-DscLocalConfigurationManager -Path c:\ -Verbose -Force
Get-DscLocalConfigurationManager

#registration key -> cert
Get-Content C:\Windows\System32\Configuration\Metaconfig.mof -Encoding Unicode
Get-Content C:\Windows\System32\Configuration\Metaconfig.mof -Encoding Unicode | Select-String 'RegistrationKey'
Get-Content c:\localhost.meta.mof | Select-String 'RegistrationKey'
Remove-Item c:\localhost.meta.mof -Force
Get-ChildItem -Path cert:\localmachine\my | Select-Object *
$thumbprint = (Get-ChildItem -Path cert:\localmachine\my).Thumbprint
Get-Content C:\Windows\system32\Configuration\DSCEngineCache.mof -Encoding Unicode | Select-String $thumbprint
Exit-PSSession
#endregion

#region download linux packages (cannot use wget on box as opengroup uses SAML auth under the covers)
Start-Process microsoft-edge:https://collaboration.opengroup.org/omi/
Start-Process https://github.com/Microsoft/PowerShell-DSC-for-Linux/releases/
#endregion

#region centOS box
#copy packages into VM (guest services needs to be enabled and linux must have 
Get-ChildItem -Path $WorkingDir -Filter *.tar.gz | ForEach-Object -Process {
    Copy-VMFile -SourcePath $_.FullName -Name CentOS7 -FileSource Host -DestinationPath /tmp
}
Start-Process ssh root@172.16.0.10
<#
    cd /tmp
    tar -xf omi-1.0.8.4.packages.tar.gz
    tar -xf dsc-1.1.1.packages.tar.gz
    yum -y localinstall omi-1.0.8.ssl_100.x64.rpm
    yum -y localinstall dsc-1.1.1-70.ssl_100.x64.rpm
    #OMI enables ssl 5986 by default, 5985 disabled by default
    more /etc/opt/omi/conf/omiserver.conf

    #open firewall
    firewall-cmd --zone=public --add-port=5986/tcp --permanent
    firewall-cmd --reload
#>

$CimSessionOption = New-CimSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck -UseSsl
$CimSession = New-CimSession -ComputerName 172.16.0.10 -Credential root -SessionOption $CimSessionOption -Authentication Basic
Get-DscLocalConfigurationManager -CimSession $CimSession
Copy-Item $WorkingDir\localhost.meta.mof -Destination $WorkingDir\172.16.0.10.meta.mof
Set-DscLocalConfigurationManager -Path $WorkingDir -CimSession $CimSession -Verbose
Get-DscLocalConfigurationManager -CimSession $CimSession
#endregion

#region Ubuntu box
<# Prep
    Start-Process ssh root@172.16.0.11
    apt install linux-tools-virtual linux-cloud-tools-virtual #enables VM File copy from host
    reboot
    Get-ChildItem -Path $WorkingDir -Filter *.tar.gz | ForEach-Object -Process {
        Copy-VMFile -SourcePath $_.FullName -Name Ubuntu1510 -FileSource Host -DestinationPath /tmp
    }
    Start-Process ssh root@172.16.0.11
    apt install build-essential
    apt install python-ctypeslib
    apt install unzip
    cd /tmp
    tar -xf omi-1.0.8.4.packages.tar.gz
    tar -xf dsc-1.1.1.packages.tar.gz
    dpkg -i omi-1.0.8.ssl_100.x64.deb
    dpkg -i dsc-1.1.1-70.ssl_100.x64.deb
#>

#copy meta.mof over scp
Start-Process scp.exe 'localhost.meta.mof root@172.16.0.11:/tmp/localhost.meta.mof'
Start-Process ssh root@172.16.0.11
<#
    cd /opt/microsoft/dsc/Scripts
    ls -l
    python GetDscLocalConfigurationManager.py
    python SetDscLocalConfigurationManager.py -configurationmof /tmp/localhost.meta.mof
    python GetDscLocalConfigurationManager.py
#>
#endregion

#region show DSC nodes in AA DSC
$AAAcct | Get-AzureRmAutomationDscNode
#endregion