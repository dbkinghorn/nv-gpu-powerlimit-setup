#!/usr/bin/env bash
# Install NVIDIA GPU powerlimit script and systemd unit file

# Putet Systems Labs
# https://pugetsystems.com
#
# Copyright 2022 Puget Systems and D B Kinghorn
# CC0 v1 license
#
# Disclaimer of Liability:
# Puget Systems and D B Kinghorn do not warrant 
# or assume any legal liability or responsibility for the use of this script

# Start install log. Will go to install.log
# (  # uncomment this line and # ) at end of file to enable logging 

if [[ $# -eq 0 || "$1" == "--help" ]]; then
    printf  '
USAGE:  sudo ./nv-powerlimit-setup.sh <powerlimit to set> \n
 <powerlimit to set> should probably be between 200 and 300 
 i.e. 280 should still give approx 95 percent performance on 350W GPU

 powerlimit will be stored in /usr/local/etc/nv-powerlimit.conf

 !!** If you do not know what all this means then do not use this script **!!

 see:
 https://www.pugetsystems.com/labs/hpc/Quad-RTX3090-GPU-Power-Limiting-with-Systemd-and-Nvidia-smi-1983/
 
 This script will;
 - make sanity checks for OS version and NVIDIA GPUs
 - create a config /usr/local/etc/nv-powerlimit.conf with the powerlimit value
 - create and install /usr/local/sbin/nv-power-limit.sh
 - create and install /etc/systemd/system/nv-power-limit.service
 - enable nv-power-limit.service
 - install is under /usr/local\n
 !!** powerlimit will be set on all NVIDIA GPUs **!!\n
'
    exit 0;
else # read the powerlimit from the command line
    POWERLIMIT=$1
fi

#set -e
set -o errexit # exit on errors
set -o errtrace # trap on ERR in function and subshell
trap 'install-error $? $LINENO' ERR
install-error() {
  echo "Error $1 occurred on $2"
  echo "YIKS! something failed!" 
  # echo "Check install.log" 
}

#set -x
#trap read debug


# eye candy
NOTECOLOR=$(tput setaf 3)     # Yellow
SUCCESSCOLOR=$(tput setaf 2)  # Green
ERRORCOLOR=$(tput setaf 1)    # Red
RESET=$(tput sgr0)

function note()    { echo "${NOTECOLOR}${@}${RESET}"; }
function success() { echo "${SUCCESSCOLOR}${@}${RESET}";}
function error()   { echo "${ERRORCOLOR}${@}${RESET}">&2; }

# Check for root/sudo
if [[ $(id -u) -ne 0 ]]; then
    echo "Please use sudo to run this script"
    exit 1
fi

#
# Sanity checks
#

note "Checking OS version ..."

source /etc/os-release
if [[ $NAME == "Ubuntu" ]] && [[ ${VERSION_ID/./}+0 -ge 1804 ]]; then
    success "[OK] ${PRETTY_NAME}";
else
    error "[STOP] Script only validated for Ubuntu 18.04 or greater"
    exit 1
fi

note "Checking for NVIDIA GPU and Driver version"

function get_driver_version() {
    nvidia-smi | grep Driver | cut -d " " -f 3;
}

if lspci | grep -q NVIDIA; then
    success "[OK] Found NVIDIA GPU"
    if [[ $(which nvidia-smi) ]]; then
        driver_version=$(get_driver_version)
        note "Driver Version = ${driver_version}"
    else
        error "[Failed] NVIDIA Driver not installed ..."
        exit 1
    fi
else
    error "[Failed] NVIDIA GPU not detected"
    exit 1
fi

#
# Create /usr/local/etc/nv-powerlimit.conf
#

note "Creating /usr/local/etc/nv-powerlimit.conf"
cat << EOF > /usr/local/etc/nv-power-limit.conf
# NVIDIA GPU powerlimit config file

# limit should be between the min and max powerlimit values
# i.e. 280 should still give over 95 percent performance on a 350W GPU

POWERLIMIT=${POWERLIMIT}

EOF

if [[ -f /usr/local/etc/nv-power-limit.conf ]]; then
    success "[OK] /usr/local/etc/nv-power-limit.conf created"
else
    error "[Failed] /usr/local/etc/nv-power-limit.conf not created"
    exit 1
fi 

note "setting permission chmod 644 on /usr/local/etc/nv-power-limit.conf"  
chmod 644 /usr/local/etc/nv-power-limit.conf


#
# Install nv-power-limit.sh 
#
note "Creating /usr/local/sbin/nv-power-limit.sh"

sudo tee /usr/local/sbin/nv-power-limit.sh << 'EOF'
#!/usr/bin/env bash

# Set power limits on all NVIDIA GPUs
# powerlimit is sorced from /usr/local/etc/nv-powerlimit.conf

# Make sure nvidia-smi exists 
command -v nvidia-smi &> /dev/null || { echo >&2 "nvidia-smi not found ... exiting."; exit 1; }

CONFIG_FILE=/usr/local/etc/nv-power-limit.conf
source ${CONFIG_FILE}
POWER_LIMIT=${POWERLIMIT}
MAX_POWER_LIMIT=$(nvidia-smi -q -d POWER | grep 'Max Power Limit' | tr -s ' ' | cut -d ' ' -f 6)

# ToDo:
# Max power limit check is blocking for multi-GPU
# will fix with arrays when I add support for setting independent power limits
#if [[ ${POWER_LIMIT%.*}+0 -lt ${MAX_POWER_LIMIT%.*}+0 ]]; then
    /usr/bin/nvidia-smi --persistence-mode=1
    /usr/bin/nvidia-smi  --power-limit=${POWER_LIMIT}
#else
#    echo 'FAIL! POWER_LIMIT set above MAX_POWER_LIMIT ... '
#    exit 1
#fi

exit 0

EOF

if [[ -f /usr/local/sbin/nv-power-limit.sh ]]; then
    success "[OK] /usr/local/sbin/nv-power-limit.sh created"
else
    error "[Failed] /usr/local/sbin/nv-power-limit.sh not created"
    exit 1
fi

note "setting permissions: chmod 744 on /usr/local/sbin/nv-power-limit.sh"
chmod 744 /usr/local/sbin/nv-power-limit.sh

#!! as workaround for systemd bug in Ubuntu 20.04 we'll run the script manually
note "Running nv-power-limit.sh"
sudo /usr/local/sbin/nv-power-limit.sh
nvidia-smi -q -d POWER 

#
# Install nv-power-limit.service
#

note "Creating /usr/local/etc/systemd/system/nv-power-limit.service"
mkdir -p /usr/local/etc/systemd/system

sudo tee /usr/local/etc/systemd/system/nv-power-limit.service << 'EOF'
[Unit]
Description=NVIDIA GPU Set Power Limit
After=syslog.target systemd-modules-load.service
ConditionPathExists=/usr/bin/nvidia-smi

[Service]
User=root
Environment="PATH=/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
ExecStart=/usr/local/sbin/nv-power-limit.sh

[Install]
WantedBy=multi-user.target

EOF

if [[ -f /usr/local/etc/systemd/system/nv-power-limit.service ]]; then
    success "[OK] /usr/local/etc/systemd/system/nv-power-limit.service created"
else
    error "[Failed] /usr/local/etc/systemd/system/nv-power-limit.service not created"
    exit 1
fi

note "setting permissions: chmod 644 on /usr/local/etc/systemd/system/nv-power-limit.service"
chmod 644 /usr/local/etc/systemd/system/nv-power-limit.service

#
# Enable nv-power-limit.service
#
note "linking /usr/local/etc/systemd/system/nv-power-limit.service to /etc/systemd/system/nv-power-limit.service"
ln -s --force /usr/local/etc/systemd/system/nv-power-limit.service /etc/systemd/system/nv-power-limit.service 

systemctl daemon-reload
systemctl start nv-power-limit.service
systemctl enable nv-power-limit.service

success "Finished setting NVIDIA GPU power-limit service"

exit 0
# ) |& tee ./install.log