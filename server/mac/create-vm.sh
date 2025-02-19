#!/usr/bin/env bash
# =============================================================================
# Copyright 2022 Hewlett Packard Enterprise
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# =============================================================================

set -euo pipefail

echo "Creating ${NAME} with ${CPU} cores and ${MEM}GB Memory, allocating ${DISKSIZE}GB for data disks."

BASEDIR=$(pwd)
VMDIR="vms/${NAME}"
BASEIMG="${HOME}/Downloads/CentOS-7-x86_64-GenericCloud-2009.qcow2"
CDROM="-cdrom ci.iso"

[ -d "${VMDIR}" ] || mkdir -p "${VMDIR}"

DISK1="${NAME}-disk1.img"
DISK2="${NAME}-disk2.img"
DISK3="${NAME}-disk3.img"
DISK4="${NAME}-disk4.img" ## DF only
SWAP="${NAME}-swap.img"
SWAPSIZE=$(expr ${MEM} / 5 + 1)
SSH_PUB_KEY=$(<../generated/controller.pub_key)

INIT_USER=$(eval "cat <<EOF
#cloud-config
preserve_hostname: False
hostname: ${NAME}
fqdn: ${NAME}.local
ssh_authorized_keys:
  - ${SSH_PUB_KEY}
EOF
" 2> /dev/null)
INIT_META=$(eval "cat <<EOF
instance-id: ${NAME}
hostname: ${NAME}.local
EOF
" 2> /dev/null)

# Common options for ssd/flash drives
DRIVE_OPTIONS="if=none,format=qcow2,discard=unmap"
IP=$(cat "${NAME}.ip" | cut -d',' -f1 || echo "")
MAC=$(cat "${NAME}.ip" | cut -d',' -f2 || echo "")

pushd "${VMDIR}" > /dev/null
  DATADISKS=""
  FIRST_RUN=$([[ -f "${DISK1}" ]] ; echo $?)
  if [[ "${FIRST_RUN}" == "1" ]]; then
    echo "${INIT_USER}" > user-data
    echo "${INIT_META}" > meta-data
    rm -f ci.iso
    hdiutil makehybrid -o ci.iso -hfs -joliet -iso -default-volume-name cidata . &> /dev/null
    qemu-img create -f qcow2 -F qcow2 -b "${BASEIMG}" "${DISK1}" &> /dev/null
    qemu-img create -f raw "${SWAP}" "${SWAPSIZE}G" &> /dev/null
    qemu-img resize "${DISK1}" 500G &> /dev/null
    if [[ "${DISKSIZE}" != "0" ]]; then
        qemu-img create -f qcow2 "${DISK2}" "${DISKSIZE}G" &> /dev/null
        qemu-img create -f qcow2 "${DISK3}" "${DISKSIZE}G" &> /dev/null
        if [ "${NAME:0:2}" == "df" ]; then
          qemu-img create -f qcow2 "${DISK4}" "${DISKSIZE}G" &> /dev/null
        fi
    # Randomize MAC for each VM
    fi
    MAC="52:54:00:$(openssl rand -hex 3 | sed 's/\(..\)/\1:/g; s/:$//')"
  fi
  if [[ "${DISKSIZE}" != "0" ]]; then
    DATADISKS="-drive file=${DISK2},id=disk2,${DRIVE_OPTIONS} -device scsi-hd,drive=disk2,bus=scsi0.0 -drive file=${DISK3},id=disk3,${DRIVE_OPTIONS} -device scsi-hd,drive=disk3,bus=scsi0.0"
    if [ "${NAME:0:2}" == "df" ]; then
      DATADISKS="${DATADISKS} -drive file=${DISK4},id=disk4,${DRIVE_OPTIONS} -device scsi-hd,drive=disk4,bus=scsi0.0"
    fi
  fi

  OUI=",mac=${MAC}"
  sudo /usr/local/bin/qemu-system-x86_64 \
    -L /opt/homebrew/Cellar/qemu/6.2.0/share/qemu \
    -M pc,acpi=on,graphics=off,mem-merge=off \
    -smp "${CPU}" \
    -m "${MEM}G" \
    -nic vmnet-shared,model=vmxnet3${OUI} \
    -device virtio-scsi-pci,id=scsi0 \
    -drive file="${DISK1}",id=disk1,"${DRIVE_OPTIONS}" -device scsi-hd,drive=disk1,bus=scsi0.0 \
    -drive file="${SWAP}",id=swap,format=raw,if=none -device scsi-cd,drive=swap,bus=scsi0.0 ${DATADISKS} \
    ${CDROM} -display none -monitor none -daemonize -serial file:console.out

    if [[ "${FIRST_RUN}" == "1" ]]; then
      while [ "${IP}" == "" ]; do
        sleep 2
        IP=$(grep "|  eth0  | True |" console.out | grep -v '/64' | cut -d'|' -f4 | tr -d ' ') || true
      done
      echo "${IP},${MAC}" >> ${BASEDIR}/${NAME}.ip
      ssh-keygen -R ${IP} &> /dev/null || true
    fi
popd > /dev/null

printf '{"hostname":"%s","ip_address":"%s"}' "${NAME}" "${IP}"

exit 0
