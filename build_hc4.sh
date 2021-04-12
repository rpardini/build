#! /bin/bash

# find damned sd-writer.

SD_DEV=
for dev in /dev/sd?; do
	DEV_DESC="$(udevadm info -a $dev | grep -e model -e manufac | grep -v Linux | cut -d "\"" -f 2 | xargs echo)"
	echo -n "- considering dev: $dev :: ${DEV_DESC} :-> "
	if [[ $DEV_DESC == *SanDisk* ]]; then
		echo "FOUND IT! $dev"
		SD_DEV=$dev
		break
	else
		echo "not it."
	fi
done
echo -n "Using device ${dev} for SD card!!" ...
sleep 2
echo "go!"

touch .ignore_changes
echo calling ./compile.sh rpardini-hc4 CARD_DEVICE=${SD_DEV} $@
./compile.sh rpardini-hc4 CARD_DEVICE=${SD_DEV} $@

