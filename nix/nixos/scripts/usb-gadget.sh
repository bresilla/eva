#!/usr/bin/env bash
# A USB network port through configfs: one NCM function on the first device
# controller. NetworkManager shares the connection over it.
#
#   eva-usb-gadget start|stop
set -eu

root=/sys/kernel/config/usb_gadget/eva

case "${1:-}" in
  start)
    modprobe libcomposite || true
    mkdir -p "$root/strings/0x409" "$root/configs/c.1/strings/0x409" "$root/functions/ncm.usb0"
    echo 0x1d6b > "$root/idVendor"
    echo 0x0104 > "$root/idProduct"
    echo eva > "$root/strings/0x409/manufacturer"
    echo "USB tethering" > "$root/strings/0x409/product"
    echo NCM > "$root/configs/c.1/strings/0x409/configuration"
    ln -sf "$root/functions/ncm.usb0" "$root/configs/c.1/"
    for controller in /sys/class/udc/*; do
      basename "$controller" > "$root/UDC"
      break
    done
    ;;
  stop)
    echo "" > "$root/UDC" || true
    rm -f "$root/configs/c.1/ncm.usb0"
    rmdir "$root/configs/c.1/strings/0x409" "$root/configs/c.1" "$root/functions/ncm.usb0" \
      "$root/strings/0x409" "$root" || true
    ;;
  *)
    echo "usage: eva-usb-gadget start|stop" >&2
    exit 2
    ;;
esac
