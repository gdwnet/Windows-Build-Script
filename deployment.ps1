#Betgenius Windows deployment script. 
#This script will deploy roles, features and software.
#Gary Williams. 9th July 2014

#Read Powershell security policy. It seems that this is required otherwise it'll prompt to change the policy
#Get-ExecutionPolicy

#Prompt person building machine for name and ip details

Write-output "Computer configuration"

$name = Read-Host 'Please enter the computer name:'
rename-computer -NewName $Name
$ip = Read-Host 'Please enter the computers IP address'
$netmask = Read-Host 'Please enter the computers subnet mask length (255.255.255.0 = 24, 255.255.254.0 = 23)'
$gateway = Read-Host 'Please enter the default Gateway'

Write-Host "Please select the domain this machine will be joined to"

[int]$menuchoice = 0
while ( $menuchoice -lt 1 -or $menuchoice -gt 2) {
    Write-Host "1. Betgenius.local"
    Write-Host "2. Betgenius.net"

[int] $menuchoice = Read-Host "Please Choose one option"}
Switch ($menuchoice) {
1{ New-NetIPAddress -interfaceAlias "Ethernet" -IPAddress $ip -prefixlength $netmask -DefaultGateway $gateway
Set-DNSClientServerAddress -interfacealias "Ethernet" -Serveraddresses "10.200.0.200,10.200.0.202"}

2{ 
    Write-Host "Please select what Environment this machine is being deployed to:"

    [int]$menuchoice = 0
    while ($menuchoice -lt 1 -or $menuchoice -gt 3) {
        Write-Host "1. Production"
        write-host "2. UAT"
        Write-Host "3. Integrations"

    [int] $menuchoice = Read-Host "Please Choose one option"}
    Switch ($menuchoice) {
        1{New-NetIPAddress -interfaceAlias "Ethernet" -IPAddress $ip -prefixlength $netmask -DefaultGateway $gateway
            Set-DNSClientServerAddress -interfacealias "Ethernet" -Serveraddresses "172.16.36.121,172.16.36.123"}
        2{New-NetIPAddress -interfaceAlias "Ethernet" -IPAddress $ip -prefixlength $netmask -DefaultGateway $gateway
            Set-DNSClientServerAddress -interfacealias "Ethernet" -Serveraddresses "10.128.23.22,10.128.23.24"}
        3{New-NetIPAddress -interfaceAlias "Ethernet" -IPAddress $ip -prefixlength $netmask -DefaultGateway $gateway
            Set-DNSClientServerAddress -interfacealias "Ethernet" -Serveraddresses "10.128.36.48,10.128.36.49"}
        default {Write-Host "Nothing Selected"}
        }
    }
}


#Deploy Windows roles and features
Start-Transcript -path C:\Windows\betgenius.ops\deployment.log
Write-output "Now installing Roles and Features"
Import-Module servermanager
Add-WindowsFeature Application-Server
Add-WindowsFeature AS-Web-Support
Add-WindowsFeature Web-Net-Ext -source c:\windows\sxs
Add-WindowsFeature Web-Asp-Net
Add-WindowsFeature NET-Framework-45-Features
Add-WindowsFeature NET-Framework-45-Core
Add-WindowsFeature MSMQ
Add-WindowsFeature MSMQ-Services
Add-WindowsFeature MSMQ-Server
Add-WindowsFeature RSAT
Add-WindowsFeature RSAT-Feature-Tools
Add-WindowsFeature RSAT-SNMP
Add-WindowsFeature SNMP-Service
Add-WindowsFeature SNMP-WMI-Provider
Add-WindowsFeature Telnet-Client
Add-WindowsFeature NET-WCF-HTTP-Activation45
Add-WindowsFeature Failover-Clustering
Add-WindowsFeature RSAT-Clustering-Mgmt

#Apply VMXNET3 buffer fix
Write-output "Now configuring VMXNET3 Rx Ring #1 Size & Small Rx Buffers"
Set-NetAdapterAdvancedProperty -DisplayName "Rx Ring #1 Size" -DisplayValue 4096
Set-NetAdapterAdvancedProperty -DisplayName "Small Rx Buffers" -DisplayValue 8192

#Check Values are in place
Get-NetAdapterAdvancedProperty -DisplayName "Rx Ring #1 Size","Small Rx Buffers"


#configure Timesync (this will move to a GPO)
#This sets the timezone to UTC, the ntp to ntp.betgenuius.net, changes the w32time service to automatic and starts it

Write-output "Now configuring time settings"
tzutil /s "UTC"
w32tm /config /manualpeerlist:ntp.betgenius.net
w32tm /config /update
cmd /c "sc config w32time start= auto"
cmd /c "sc start w32time"


Write-output "Now installing Software packages"

#Now lets bring in the registry key that has the build version
regedit /s "c:\windows\betgenius.ops\registry\build_ver_key.reg"

#Betgenius MSMQ Administration service
regedit /s "c:\windows\betgenius.ops\registry\bg_msmq_admin"

#And now the software

#Graphite  Disabled as per Ian Cross request.
#msiexec /i "c:\windows\betgenius.ops\software\GraphitePerformanceMonitor.Installer.msi" /passive

#.NETFramework 4.5.2
#"C:\Windows\BetGenius.Ops\software\dotNetfx452.exe" -ArgumentList /s, /q,/qb, /norestart  -NoNewWindow -Wait 
cmd /c "c:\windows\betgenius.ops\software\NDP452-KB2901907-x86-x64-AllOS-ENU" /norestart /passive

#Notepad++
Start-process "C:\windows\betgenius.ops\software\npp.6.5.5.installer.exe" /S -NoNewWindow -Wait

#Install Nagios Client and copy across the valid .ini file
Start-process "c:\windows\betgenius.ops\software\NSClient++-0.3.8-x64.msi" /passive
Start-Sleep -s 15 #Pause required or the file copy happens before the install completes!
cmd /c copy "c:\windows\betgenius.ops\software\nsc.ini" "c:\program files\nsclient++" /Y

#Microsoft Visual C++ 2008 Redistributable - x86 9.0.30729.4148 9.0.30729.4148
Start-process "C:\windows\betgenius.ops\software\vcredist_x64.exe" /q:a  -NoNewWindow -Wait

#Google Chrome
c:\windows\betgenius.ops\software\GoogleChromeStandaloneEnterprise.msi /passive

#Pause script for 15 seconds before moving on
Start-Sleep -s 15

#Microsoft F Share redist
Start-process "C:\windows\betgenius.ops\software\fsharp_redist" /q:a  -NoNewWindow -Wait

#CheckMK Agent
Start-process "C:\windows\betgenius.ops\software\check-mk-agent-1.2.2p2.exe" /S -NoNewWindow -Wait

#ASP.Net Web pages
msiexec /i "c:\windows\betgenius.ops\software\AspNetWebPages.msi" /passive

#Configure SNMP
$nagiosPermitted = $false
$permittedManagers = Get-Item HKLM:\SYSTEM\CurrentControlSet\services\SNMP\Parameters\PermittedManagers
$valueNames = $permittedManagers.GetValueNames()
if($valueNames) {
    if($valueNames | % { $permittedManagers.GetValue($_) } | ? { $_ -eq "192.168.246.5" }) {
        #Nagios allowed specifically
        $nagiosPermitted = $true
    }
} else {
    #All hosts permitted as no hosts specifically set
    $nagiosPermitted = $true
}

if(-not $nagiosPermitted) {
    if($valueNames) {
        $nextValueName = ($valueNames | Measure-Object -Maximum).Maximum + 1
    } else {
        $nextValueName = "1"
    }
    reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\SNMP\Parameters\PermittedManagers" /v $nextValueName /t REG_SZ /d 192.168.246.5 /f | Out-Null
}

$validCommunities = Get-Item HKLM:\SYSTEM\CurrentControlSet\services\SNMP\Parameters\ValidCommunities
if(-not $validCommunities.GetValue("status")) {
    reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\SNMP\Parameters\ValidCommunities" /v status /t REG_DWORD /d 4 /f | Out-Null
}


#Install Cert - not required as this is now in the wim itself.
#certmgr -add c:\windows\betgenius.ops\Certs\uat.betgenius.com\uat_cert.cer -s -r localMachine trustedpublisher

#Enable PS Remoting Stuffs
Enable-PSRemoting -Force
Set-ExecutionPolicy Unrestricted -Force
Set-WSManQuickConfig -force
Enable-WSManCredSSP -Role Server -Force


#Stop here as there will be  reboot with the vmware tools

Write-output "Now installing VMWare tools which will take approx 5 minutes. When complete a reboot will be forced"

#Pause script for 15 seconds before moving on
Start-Sleep -s 15

#Configure VMWare tools - THIS WILL CAUSE A REBOOT SO SHOULD BE LAST
& "C:\windows\betgenius.ops\software\VMWare_Tools\setup.exe" /S /v /qn

#Pause script for 45 seconds before moving on
Start-Sleep -s 45
