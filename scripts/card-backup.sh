#!/usr/bin/env bash

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# IMPORTANT:
# Run the install-little-backup-box.sh script first
# to install the required packages and configure the system.

# Specify devices and their their mount points
# as well as other settings

STATE=0

LED0="/sys/class/leds/beaglebone:green:usr0"
LED1="/sys/class/leds/beaglebone:green:usr1"
LED2="/sys/class/leds/beaglebone:green:usr2"
LED3="/sys/class/leds/beaglebone:green:usr3"
LED="/sys/class/leds/beaglebone:green:usr"

reset_LEDs() {
  sudo sh -c "echo none > $LED0/trigger"
  sudo sh -c "echo 0 > $LED0/brightness"
  sudo sh -c "echo none > $LED1/trigger"
  sudo sh -c "echo 0 > $LED1/brightness"
  sudo sh -c "echo none > $LED2/trigger"
  sudo sh -c "echo 0 > $LED2/brightness"
  sudo sh -c "echo none > $LED3/trigger"
  sudo sh -c "echo 0 > $LED3/brightness"
}

welcome_LEDs() {
  reset_LEDs
  sleep 1
  sudo sh -c "echo 1 > $LED0/brightness"
  sudo sh -c "echo 1 > $LED1/brightness"
  sudo sh -c "echo 1 > $LED2/brightness"
  sudo sh -c "echo 1 > $LED3/brightness"
  sleep 1
  sudo sh -c "echo 0 > $LED0/brightness"
  sudo sh -c "echo 0 > $LED1/brightness"
  sudo sh -c "echo 0 > $LED2/brightness"
  sudo sh -c "echo 0 > $LED3/brightness"
  sleep 0.5
}

off_LEDs() {
  INDEX=$1
  for i in `seq $INDEX 3`
  do
    sudo sh -c "echo 0 > $LED$i/brightness"
  done
}

show_progress() {
  $PROGRESS=$1
  if [ $PROGRESS -gt 0 ] && [ $PROGRESS -lt 24 ]; then
      STEP=0
    elif [ $PROGRESS -gt 25 ] && [ $PROGRESS -lt 49 ]; then
      STEP=1
    elif [ $PROGRESS -gt 50 ] && [ $PROGRESS -lt 74 ]; then
      STEP=2
    elif [ $PROGRESS -gt 75 ] && [ $PROGRESS -lt 100 ]; then
      STEP=3
    fi
    if [ $STATE -eq 4] ; then
      off_LEDs $STEP
      STATE=$STEP
    else
      STATE=$((STATE+1))
    fi
}

activate_cylon_leds() {
  cylon_leds & CYLON_PID=$!
}

deactivate_cylon_leds() {
  if [ -e /proc/$CYLON_PID ]; then
      kill $CYLON_PID > /dev/null 2>&1
  fi
}

STORAGE_DEV="sda1" # Name of the storage device
STORAGE_MOUNT_POINT="/media/storage" # Mount point of the storage device
CARD_DEV="mmcblk0p1" # Name of the storage card
CARD_MOUNT_POINT="/media/card" # Mount point of the storage card
SHUTD="5" # Minutes to wait before shutdown due to inactivity

welcome_LEDs

# Set the LED 0 to blink at 1000ms to indicate that the BB is on and waiting for storages (shutdown counter on)
sudo sh -c "echo heartbeat > $LED0/trigger"
sudo sh -c "echo timer > $LED0/trigger"
sudo sh -c "echo 1000 > $LED0/delay_on"

# Shutdown after a specified period of time (in minutes) if no device is connected.
sudo shutdown -h $SHUTD "Shutdown is activated. To cancel: sudo shutdown -c"

# Wait for a USB storage device (e.g., a USB flash drive, HDD)
STORAGE=$(ls /dev/* | grep "$STORAGE_DEV" | cut -d"/" -f3)
while [ -z "${STORAGE}" ]
  do
  sleep 1
  STORAGE=$(ls /dev/* | grep "$STORAGE_DEV" | cut -d"/" -f3)
done

# When the USB storage device is detected, mount it
mount /dev/"$STORAGE_DEV" "$STORAGE_MOUNT_POINT"

# Cancel shutdown
sudo shutdown -c

# Set the USER LED 0 to static on to indicate that the storage device has been mounted (shutdown counter off)
sudo sh -c "echo none > $LED0/trigger"
sudo sh -c "echo 1 > $LED0/brightness"

# Set the USER LED 1 to blink at 1000ms to indicate that the BB is waiting for card reader or a camera
sudo sh -c "echo heartbeat > $LED1/trigger"
sudo sh -c "echo timer > $LED1/trigger"
sudo sh -c "echo 1000 > $LED1/delay_on"

# Wait for a card reader or a camera
# takes first device found
CARD_READER=($(ls /dev/* | grep "$CARD_DEV" | cut -d"/" -f3))
until [ ! -z "${CARD_READER[0]}" ]
  do
  sleep 1
  CARD_READER=($(ls /dev/* | grep "$CARD_DEV" | cut -d"/" -f3))
done

# If the card reader is detected, mount it and obtain its UUID
if [ ! -z "${CARD_READER[0]}" ]; then
  mount /dev"/${CARD_READER[0]}" "$CARD_MOUNT_POINT"
  
  # Set the USER LED 1 to static on to indicate that the SDCard has been mounted
  sudo sh -c "echo none > $LED1/trigger"
  sudo sh -c "echo 1 > $LED1/brightness"

  CARD_COUNT=$(find $CARD_MOUNT_POINT/ -type f | wc -l)

  # Create  a .id random identifier file if doesn't exist
  cd "$CARD_MOUNT_POINT"
  if [ ! -f *.id ]; then
    random=$(echo $RANDOM)
    touch $(date -d "today" +"%Y%m%d%H%M")-$random.id
  fi
  ID_FILE=$(ls *.id)
  ID="${ID_FILE%.*}"
  cd

  # Set the backup path
  BACKUP_PATH="$STORAGE_MOUNT_POINT"/"$ID"
  STORAGE_COUNT=$(find $BACKUP_PATH/ -type f | wc -l)
  # Perform backup using rsync
  rsync -avh --info=progress2 --exclude "*.id" "$CARD_MOUNT_POINT"/ "$BACKUP_PATH" &
  pid=$!

  reset_LEDs
  
  while kill -0 $pid 2> /dev/null
    do
    STORAGE_COUNT=$(find $BACKUP_PATH/ -type f | wc -l)
    PERCENT=$(expr 100 \* $STORAGE_COUNT / $CARD_COUNT)
    sudo sh -c "echo $PERCENT"
    show_progress $PERCENT
    sleep 1
  done
  sudo sh -c "echo 1 > $LED3/brightness"
fi

# Shutdown
sync
umount /media/card
umount /media/storage
sync
shutdown -h now
