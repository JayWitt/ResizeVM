#
#Sample scripts are not supported under any Microsoft standard support program or service. 
#The sample scripts are provided AS IS without warranty of any kind. Microsoft disclaims all 
#implied warranties including, without limitation, any implied warranties of merchantability
#or of fitness for a particular purpose. The entire risk arising out of the use or performance
#of the sample scripts and documentation remains with you. In no event shall Microsoft, its 
#authors, or anyone else involved in the creation, production, or delivery of the scripts be 
#liable for any damages whatsoever (including, without limitation, damages for loss of business
#profits, business interruption, loss of business information, or other pecuniary loss) arising
#out of the use of or inability to use the sample scripts or documentation, even if Microsoft 
#has been advised of the possibility of such damages.

#Currently does not handle the following features of the VM
# - Monitoring 
#     OS Guest Diagnostics
# - Extensions 
#     Need more work on Extensions as
# - Only works for Windows machines

# AVAILABILITY SET NOTE:
# 
#  +-------------------+-----------------------------------------+------------------------------------------------+
#  |                   | $asForce = True                         | $asForce = False                               | 
#  +-------------------+-----------------------------------------+------------------------------------------------+
#  | $asName is blank  | It will remove the VM from any AS.      | It will keep the VM in the existing AS if the  |
#  |                   |                                         | old VM was a part of an AS already. If not     |
#  |                   |                                         | new VM will remain without an AS.              |
#  +-------------------+-----------------------------------------+------------------------------------------------+
#  | $asName has value | It will move the VM to the new AS even  | If old VM was a part of an AS, then it will    |
#  |                   | if the old VM was in a previous AS.     | remain there. If no AS is assigned, then it    |
#  |                   |                                         | will add the VM to the AS.                     |
#  +-------------------+-----------------------------------------+------------------------------------------------+
#
#


# Created By: Jay Witt
# Updated on 2/25/2019


#################################
#################################
#CHANGE BELOW VARIABLES

$vmName = "<VMName>"     ## Name of the VM to be moved
$rgName = "<Resource Group Name>"    ## Name of Resource Group that the VM is in
$asForce = $false         ## Force the Availability Set to be set. (See Availability Set note above)
$asName = ""       ## Name of Availability Set. (See Availability Set note above)
$vmNewSize = "<New Size>"       ## The new size of the VM. Leave blank to leave it the same.

#################################
#################################
$newVMName = $vmname  ## This script can also rename the computer name. Put new VMName here or replace it with the $vmname variable if you are keeping the name the same.


if ($asName -ne "") {
    if ((Get-AzureRmAvailabilitySet -ResourceGroupName $rgName -Name $asName -ErrorAction Ignore) -eq $null) {
        Write-Host "WARNING!! -- Availability Set does not exist in the same Resource Group as the VM!" -foregroundcolor red
    }
}

$oldVM = Get-AzureRmVm -ResourceGroupName $rgName -Name $vmName

## Capture the original VM settings to files
write-host "Capturing original VM Settings to files" -ForegroundColor Cyan

$Random = Get-Random

$oldVM | ConvertTo-Json | out-file .\Before-$vmName-$Random-VM.json
$oldVM.NetworkProfile | ConvertTo-Json | out-file .\Before-$vmName-$Random-Network.json
$oldVM.DiagnosticsProfile  | ConvertTo-Json | out-file .\Before-$vmName-$Random-Diag.json
$oldVM.StorageProfile | ConvertTo-Json | out-file .\Before-$vmName-$Random-Storage.json
$oldVM.Extensions | ConvertTo-Json | out-file .\Before-$vmName-$Random-Extensions.json

## Store the original Vm options

$location = $oldVM.Location
if ($vmNewSize -ne "") {
        $vmsize = $vmNewSize
    } else {
        $vmSize = $oldVM.HardwareProfile.VmSize
    }
$nicName = $oldvm.NetworkProfile.NetworkInterfaces.id.split("/")[$oldvm.NetworkProfile.NetworkInterfaces.id.split("/").count-1]
$nic = Get-AzureRmNetworkInterface -name $nicName -ResourceGroupName $rgname
$subnetID = $nic.IpConfigurations.subnet.id
$vnetName = $nic.IpConfigurations.subnet.id.Split("/")[$nic.IpConfigurations.subnet.id.Split("/").count-3]
$vhdName = $oldvm.StorageProfile.OsDisk.name
$managedDiskID = $oldvm.StorageProfile.OsDisk.ManagedDisk.id
$Diag = $oldvm.DiagnosticsProfile
$DiagSettings = $oldVM.DiagnosticsProfile.BootDiagnostics.Enabled
$DiagStorage = (([System.Uri]$oldvm.DiagnosticsProfile.BootDiagnostics.StorageUri).Authority) -replace ".blob.core.windows.net"
$Extension = $oldVm.Extensions
$DataDiskLayout = $oldvm.StorageProfile.DataDisks
$LicenseType = $oldvm.LicenseType
$tags = $oldvm.Tags
$oldAS = $oldvm.AvailabilitySetReference

$oldVMName = $oldVM.Name
if ($oldvm.Name -ne $vmName) {
    write-host "    VMName: $oldVMName [New Name = $vmName]" -ForegroundColor Magenta
} else {
    write-host "    VMName: $oldVMName" -ForegroundColor Magenta
}
$oldNICcount = ($oldVM.NetworkProfile.NetworkInterfaces).count
write-host "    Nics: $oldNICCount" -ForegroundColor Magenta
write-host "    Current Availability Set: $oldAS" -ForegroundColor Magenta
write-host "    Tags: "$tags -ForegroundColor Magenta
write-host "    Primary NIC VNet: $VNetName" -ForegroundColor Magenta
$subnetname = $subnetID.split("/")[$subnetID.split("/").count-1]
write-host "    Primary NIC Subnet: $subnetName" -ForegroundColor Magenta
write-host " "

## Delete the Compute side of the VM
write-host "About to delete the compute of old VM" -ForegroundColor Yellow

Read-Host -Prompt "Are you sure you want to continue? [Press enter to continue]"
write-host "Deleting the compute of old VM" -ForegroundColor Cyan

Remove-AzureRmVm -Name $vmName -Force -ResourceGroupName $rgName | Out-Null

## Get the Availability Set and add it to new VM object
write-output "Working on Availability Set to new VM Object"

if ($asName -eq "") {
    if ($asForce) {
        write-host "No AS Specified / Forced - No AS used"
        $newVM = New-AzureRmVmConfig -VMName $NewVMName -VMSize $vmSize
    } else {
        if ($oldAS -eq $null) {
            write-host "Found No AsName / NOT Forced / Machine not in AS - No AS used since VM shouldn't be a part of an AS"
            $newVM = New-AzureRmVmConfig -VMName $NewVMName -VMSize $vmSize
        } else {
            write-host "Found No AsName / NOT Forced / Had old AS so using old AS"
            $newVM = New-AzureRmVmConfig -VMName $NewVMName -VMSize $vmSize -AvailabilitySetId $oldAS.id
        }
    }
} else {
    if ($asForce) {
        write-host "Found AsName / Forced - Using new AS" 
            $as = Get-AzureRmAvailabilitySet -ResourceGroupName $rgName -Name $asName
            $newVM = New-AzureRmVmConfig -VMName $NewVMName -VMSize $vmSize -AvailabilitySetId $as.Id
    } else {
        if ($oldAS -eq $null) {
            if ($asName -ne "") {
                write-host "Found AsName / NOT Forced / Machine not in AS but new one is specified so using it"
                $as = Get-AzureRmAvailabilitySet -ResourceGroupName $rgName -Name $asName
                $newVM = New-AzureRmVmConfig -VMName $NewVMName -VMSize $vmSize -AvailabilitySetId $as.Id             
            } Else {
                write-host "Found AsName / NOT Forced / Machine not in AS - No AS used"
                $newVM = New-AzureRmVmConfig -VMName $NewVMName -VMSize $vmSize
            }
        } else {
            write-host "Found AsName / NOT Forced / Had old AS so using old AS"
            $newVM = New-AzureRmVmConfig -VMName $NewVMName -VMSize $vmSize -AvailabilitySetId $oldAS.id
        }
    }
}


## Attach old VM OS Disk to VM object
write-host "Attaching OS Drive to new VM Object" -ForegroundColor Cyan
Set-AzureRmVmOSDisk -VM $newVM -Name $vhdName -ManagedDiskId $managedDiskID -Windows -CreateOption Attach | Out-Null

## Attach old NICs to VM object
write-host "Adding old VM NICs to new VM Object" -ForegroundColor Cyan

foreach ($nicCard in $oldVM.NetworkProfile.NetworkInterfaces) {
    if ($nicCard.Primary) {
        $tmpNIC = $nicCard.Id
        $newVM = Add-AzureRmVMNetworkInterface -VM $newVM -Id $nicCard.Id -Primary
    }
    else{
        $tmpNIC = $nicCard.Id
        $newVM = Add-AzureRmVMNetworkInterface -VM $newVM -Id $nicCard.Id
    }
}

## Set the appropriate Boot Diagnostics to VM Object
write-host "Adding Boot Diagnostics to new VM Object" -ForegroundColor Cyan

if ($DiagSettings) {
    Set-AzureRmVMBootDiagnostics -vm $newVM -Enable -ResourceGroupName $rgName -StorageAccountName $DiagStorage | Out-Null
} else {
    Set-AzureRmVMBootDiagnostics -vm $newVM -Disable | Out-Null
}

## Setup the Data Disks (in the right order) to the VM Object
write-host "Adding Data Disks to new VM Object" -ForegroundColor Cyan

Foreach ($Disk in $DataDiskLayout)
{
    $ddID = $Disk.ManagedDisk.id
    $ddName = $DIsk.Name
    $ddLUN = $disk.Lun
    $ddCaching = $disk.Caching
    $ddSize = $disk.DiskSizeinGB

    $newVM = Add-AzureRmVMDataDisk -VM $newVM -Name $ddName -CreateOption Attach -ManagedDiskId $ddID -Lun $ddLUN -Caching $ddCaching -DiskSizeInGB $ddsize
}

## Depending on the use of AHUB, build the VM Object
write-host "Creating VM based on new VM Object (with original AHUB Settings)" -ForegroundColor Cyan

if ($LicenseType -eq $null)
    {
        New-AzureRmVm -ResourceGroupName $rgName -Location $location -VM $newVM -Tag $tags | out-null
    } else
    {
        New-AzureRmVm -ResourceGroupName $rgName -Location $location -VM $newVM -LicenseType $LicenseType -Tag $tags | out-null
    }

