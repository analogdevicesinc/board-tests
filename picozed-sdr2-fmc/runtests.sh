#!/bin/bash
#
# Test suite for the PicoZed SDR2 FMC board.
#
# To add more tests, add new functions with names ending in "_test" and they
# will get automatically run.

LED_PATH="/sys/class/leds/led*"

Display_test() {
	# requires xrandr
	export DISPLAY=":0.0" XAUTHORITY="/var/run/lightdm/root/:0"
	[[ -n $(xrandr | grep '^HDMI-0 connected') ]]
}

Audio_test() {
	# requires sox and scipy/numpy for python3
	local AUDIODEV fifo audio_tmp1 audio_tmp2
	local FREQ=500 freq1 freq2 freq1diff freq2diff
	local ret1=0 ret2=0

	# fix levels for output/input
	alsactl restore -c 1 -f adau1761.state &>/dev/null
	if [[ $? -ne 0 ]]; then
		echo "Failed restoring alsa device state"
		return 1
	fi

	export AUDIODEV=plughw:CARD=ADAU1761,DEV=0
	fifo=$(mktemp --suffix=.fifo)
	rm -f "${fifo}" && mkfifo "${fifo}"
	audio_tmp1=$(mktemp --suffix=tmp1.wav)
	audio_tmp2=$(mktemp --suffix=tmp2.wav)

	# record from the headphone jack to line in (upper right to upper left)
	amixer -q -c 1 set Lineout off
	amixer -q -c 1 set Headphone on
	amixer -q -c 1 set Headphone 100%
	play -V0 -q -c 1 -r 48000 -b 16 -n synth 3 sine ${FREQ} > "${fifo}" &
	cat "${fifo}" | rec -q -c 1 "${audio_tmp1}" silence 1 0.1 3% 1 3.0 3%

	# record from the lineout jack to mic in (lower right to lower left)
	amixer -q -c 1 set Headphone off
	amixer -q -c 1 set Lineout on
	amixer -q -c 1 set Lineout 100%
	play -V0 -q -c 1 -r 48000 -b 16 -n synth 3 sine ${FREQ} > "${fifo}" &
	cat "${fifo}" | rec -q -c 1 "${audio_tmp2}" silence 1 0.1 3% 1 3.0 3%

	# pull the frequencies from the recorded tones and compare them
	freq1=$(./wav_tone_freq "${audio_tmp1}" 2)
	freq2=$(./wav_tone_freq "${audio_tmp2}" 2)
	freq1diff=$(( FREQ - freq1 ))
	freq2diff=$(( FREQ - freq2 ))
	if [[ ${freq1diff#-} -gt 2 ]]; then
		echo "Headphone to line in failed: sent freq ${FREQ} Hz, received freq ${freq1} Hz"
		ret1=1
	fi
	if [[ ${freq2diff#-} -gt 2 ]]; then
		echo "Lineout to mic in failed: sent freq ${FREQ} Hz, received freq ${freq2} Hz"
		ret2=1
	fi

	# clean up
	rm -f "${fifo}" "${audio_tmp1}" "${audio_tmp2}"
	# restore levels for output/input
	alsactl restore -c 1 -f adau1761.state &>/dev/null

	return $(( ret1 + ret2 ))
}

USB_test() {
	local ret tmpfile tmpfile2 filename chksum new_chksum

	[[ -e /dev/sda ]] || return 1

	# create random 1MB data file
	tmpfile=$(mktemp)
	filename=$(basename "${tmpfile}")
	dd if=/dev/urandom of="${tmpfile}" bs=1024 count=1024 &>/dev/null
	chksum=$(md5sum "${tmpfile}" | cut -d' ' -f1)

	# copy data to USB drive and then copy it back
	dd if="${tmpfile}" of=/dev/sda bs=1024 count=1024 &>/dev/null
	sync
	echo 3 > /proc/sys/vm/drop_caches
	tmpfile2=$(mktemp)
	dd if=/dev/sda of="${tmpfile2}" bs=1024 count=1024 &>/dev/null
	sync
	echo 3 > /proc/sys/vm/drop_caches
	new_chksum=$(md5sum "${tmpfile2}" | cut -d' ' -f1)
	rm -f "${tmpfile}" "${tmpfile2}"

	[[ ${chksum} == ${new_chksum} ]] && ret=0 || ret=1
	return ${ret}
}

Ethernet_test() {
	# requires network namespace support enabled in the kernel and an Ethernet
	# cable connecting both jacks
	local ret

	service network-manager stop &>/dev/null

	# create a network namespace and move eth1 into it
	ip netns add test
	ip link set eth1 netns test

	# bring up the interfaces
	ip netns exec test ifconfig eth1 192.168.1.99 up
	ifconfig eth0 192.168.1.100 up
	sleep 3

	# ping between namespaces to force packets over the wire
	ping -c 3 192.168.1.99 &>/dev/null
	ret=$?

	ip netns del test
	service network-manager restart &>/dev/null
	return ${ret}
}

button_test() {
	# TODO: interactive button testing
	# export gpios
	true
	# unexport gpios
}

ret=0
tests=$(compgen -A function | grep '_test$')

pushd "$(dirname $(readlink -f "${0}"))" >/dev/null
# run all test functions
for test_func in ${tests[@]}; do
	test_name=${test_func//_/ }
	echo -n "RUNNING: ${test_name} "
	eval ${test_func}
	if [[ $? -eq 0 ]]; then
		echo "PASSED"
	else
		echo "FAILED"
		ret=1
	fi
done
popd >/dev/null

# determine if any test functions failed
if [[ ${ret} -eq 0 ]]; then
	echo "ALL TESTS PASSED"
	# solid LEDs for passing test suite
	for led in ${LED_PATH}; do
		echo none > "${led}"/trigger
		echo 100 > "${led}"/brightness
	done
else
	echo "TEST(S) FAILED"
	# flashing LEDs for failing test suite
	for led in ${LED_PATH}; do
		echo heartbeat > "${led}"/trigger
	done
fi

exit ${ret}
