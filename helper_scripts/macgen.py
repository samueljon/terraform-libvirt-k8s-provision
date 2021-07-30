#!/usr/bin/python3
# macgen.py script to generate a MAC address for kvm guest virtual machines
#
# Modified version from https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/6/html/virtualization_administration_guide/sect-virtualization-tips_and_tricks-generating_a_new_unique_mac_address
import random
#
def randomMAC():
            # 52:54:00
	mac = [ 0x52, 0x54, 0x00,
		random.randint(0x00, 0x7f),
		random.randint(0x00, 0xff),
		random.randint(0x00, 0xff) ]
	return ':'.join(map(lambda x: "%02x" % x, mac))
#
print(randomMAC())
