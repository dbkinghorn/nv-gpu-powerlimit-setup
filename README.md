# nv-gpu-powerlimit-setup

## NVIDIA GPU Powerlimit Systemd Setup Script

This scrip can be used to install a systemd unit file that will set the power-limit for NVIDIA GPUs at system boot.

**The bash script is for Ubuntu >= 18.04 but should be easy to adapt to other distributions**

This script will;

- make sanity checks for OS version and NVIDIA GPUs
- create a config /usr/local/etc/nv-powerlimit.conf with the powerlimit value
- create and install /usr/local/sbin/nv-power-limit.sh
- create and install /etc/systemd/system/nv-power-limit.service
- enable nv-power-limit.service
- install is under /usr/local

!!** powerlimit will be set on all NVIDIA GPUs **!!

### ToDo:

- Allow GPUs and power limits to be set independently.
  i.e. `./nv-gpu-powerlimit-setup.sh --gpus 0,1,2,3 --powerlimit 300,250,250,250`

## Motivation:

The higher end NVIDA RTX desktop GPUs like the RTX3090, A5000, etc.. Make wonderful compute devises in a multi-GPU setup. However the default power limits are set very high. As much as 350W! Those high power limits can strain the the capability of a system power supply cooling capability and possibly even overload the circuit that the system is is plugged into.

Our testing has shown that lowering the power limit to more reasonable values has very little impact on performance. [https://www.pugetsystems.com/labs/hpc/Quad-RTX3090-GPU-Wattage-Limited-MaxQ-TensorFlow-Performance-1974/](https://www.pugetsystems.com/labs/hpc/Quad-RTX3090-GPU-Wattage-Limited-MaxQ-TensorFlow-Performance-1974/)

![RTX 3090 powerlimit vs performance ](./RTX-3090-powerlimit-vs-performance.jpeg)

## Usage:

```
./nv-gpu-powerlimit-setup.sh --help

USAGE:  sudo ./nv-powerlimit-setup.sh <powerlimit to set>

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
 - install is under /usr/local

 !!** powerlimit will be set on all NVIDIA GPUs **!!

```

The setup script will do the initial setup for automatically setting power limits at during system boot. The script can be used again to reset the power limit. The power limit can also be changed in /usr/local/etc/nv-powerlimit.conf to the desired value and that value will be set at next reboot.
