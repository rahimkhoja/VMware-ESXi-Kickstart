# Accept the VMware End User License Agreement
vmaccepteula

# Clear All Disk Partitions
clearpart --alldrives --overwritevmfs

# Install on the First Local Disk available on Host
install --firstdisk --overwritevmfs

# Install ESXi on the first (USB) disk, ignore any SSD and do not create a VMFS
#install --ignoressd --firstdisk=usb --overwritevmfs --novmfsondisk

# Set VMFS on Specific Disk
#partition datastoreM2 --onfirstdisk=local

# Set the Root Password
# For generating encrypted pasword use:
# openssl passwd -1 $ROOT_PASSWORD
# How does this work? https://unix.stackexchange.com/a/174081
rootpw --iscrypted $1$fgJ5Imnx$XPCH6KFUC.39EFG7gMB4g0

# Set Unencrypted (Plain Text) Password (Not Recommended)
#rootpw SolarWinds123 

# ESXi Product Key
vim-cmd vimsvc/license --set XXXX-XXXX-XXXX-XXXX-XXXX # Update This Line
serialnum --esx=XXXX-XXXX-XXXX-XXXX-XXXX # Update This Line

# Set the keyboard
keyboard 'US Default'

# Host Network Settings 
# Set the network to DHCP on the first network adapter
# Generic DHCP Option:
network --bootproto=dhcp --device=vmnic0
# Advanced static setup:
# network --bootproto=static --device=vmnic0 --ip=10.10.70.206 --netmask=255.255.0.0 --gateway=10.10.0.1 --nameserver=8.8.8.8 --hostname=cloud0.domain.local
reboot

#Firstboot section 1
%firstboot --interpreter=busybox
sleep 30

# Suppress Shell Warning
esxcli system settings advanced set -o /UserVars/SuppressShellWarning -i 1

# Set ESXi Shell timeout
#esxcli system settings advanced set -o /UserVars/ESXiShellTimeOut -i 1

# Enable & Start Remote ESXi Shell (SSH)
vim-cmd hostsvc/enable_ssh
vim-cmd hostsvc/start_ssh

# Enable & Start ESXi Shell (TSM)
vim-cmd hostsvc/enable_esx_shell
vim-cmd hostsvc/start_esx_shell

# Add DNS Nameservers to resolve.conf
cat << EOF > /etc/resolv.conf
search domain.local # Update This Line

nameserver 8.8.8.8 # Update This Line

options timeout:3
options attempts:1

EOF

# Setup NTP Configuration
cat << EOF > /etc/ntp.conf
restrict default kod nomodify notrap noquerynopeer
restrict 127.0.0.1
server pool.ntp.org # Update This Line

EOF

# Enable Network Time Daemon (NTPD)
/sbin/chkconfig ntpd on

# Install SSH Keys If Needed
#echo 'from="1.2.3.4,5.6.7.8/8" ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEArNxkKzzjRzvl/SjQUEpSOwsXNeyNYWUNHYYTInMV2OEWyAxf6tVzIPnmBi1ytGtdbRw260AMEtDu3V5uPBV5B4O2nkVy1doXQBvNSiLkf09P3iu9jcLnK0/xeGDe2BKf8CtSDD1Oz3FwiqG93oqh1hICe1IJFP9I/VyhiV+4frOPO7aHASaMRKL1qntfSxmS4jN/Ps/cm6pn4+K/JJ9z3KVLI2b0Q2nAS25R5xD/lZcsXnT863m6Cyhodydd+fzpyzTCqZSXGQA3nHuIyMJv6XJjNGaXQz2X7QukdZKoDOf2/0ghPnzD4vOUoor2LdXTgI1GsugaXIncUYlNdRMTDQ== root@domain.local' >> /etc/ssh/keys-root/authorized_keys

# Setup Basic Network (Add Uplinks to vSwitches)
esxcli network vswitch standard uplink add --uplink-name vmnic2 --vswitch-name vSwitch0
esxcli network vswitch standard uplink add --uplink-name vmnic3 --vswitch-name vSwitch0
esxcli network ip dns search add --domain=domain.local # Update This Line
esxcli network ip dns server add --server=8.8.8.8 # Update This Line

# Set System FQDN Hostname
esxcli system hostname set --fqdn=cloud0.domain.local

# Enter Maintenance Mode
esxcli system maintenanceMode set -e true
vim-cmd hostsvc/maintenance_mode_enter

# Firstboot Section 2 
%firstboot --interpreter=busybox

# SNMP Setup
esxcli system snmp set --enable true
sleep 1
esxcli system snmp set --hwsrc sensors
sleep 1
esxcli system snmp set --hwsrc indications
sleep 1
esxcli system snmp set --communities 'communitystring'  # Update This Line
sleep 1
esxcli system snmp set --targets 'IP/URL to SNMP Target' # Update This Line
sleep 1
esxcli network firewall ruleset set --ruleset-id snmp --allowed-all true
sleep 1
esxcli network firewall ruleset set --ruleset-id snmp --enabled true
sleep 1
/etc/init.d/snmpd restart

# Enable Simple Network Management Protocal 
/sbin/chkconfig snmpd on

# Disable IPv6
#esxcli network ip set --ipv6-enabled=false

# Allow HTTP access to the WAN
esxcli network firewall ruleset set -e true -r httpClient

#Install 3rd Party Plugins (VIB)
#esxcli software vib install -v http://url.to.file

# HT Aware Mitigation
esxcli system settings kernel set -s hyperthreadingMitigation -v TRUE

# Detect ESXi Version
ESXIVER=$(esxcli --version | awk '{print $4}')
echo "Detected ESX Version: $ESXIVER"

# Update ESXi
ESXIUPDATE=$(esxcli software sources profile list --depot=https://hostupdate.vmware.com/software/VUM/PRODUCTION/main/vmw-depot-index.xml | grep "$ESXIVER" | grep "standard" | awk '{ print $5 " " $1 }' | sort | awk '{print $2}' | tail -1)
ESXIUPLEN=$(echo -n "$ESXIUPDATE" | wc -m)

if [ "$ESXIUPLEN" -gt 8 ]; then
    echo "Updating to $ESXIUPDATE"
    esxcli software profile update --depot=https://hostupdate.vmware.com/software/VUM/PRODUCTION/main/vmw-depot-index.xml --profile="$ESXIUPDATE"
else
    echo "No Update Detected!"
fi

# Reboot and Restart in Normal Operating Mode 
sleep 30
reboot
