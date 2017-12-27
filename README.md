pimatic-ble-itag
================

Pimatic Plugin that monitors availability of iTag BLE devices.

Unfortunately the iTag shuts down some minutes after disconnecting, so it can not be used as a beacon.
However once connected the button and buzzer can be used.

I'm working with this device:
On the device it says:
Serial Number String: 20170414
Hardware Revision String: FD-001-S-N V1.5

In the firmware it says:
Manufacturer Name String: 3231S FDQ
Model Number String: BT 4.0
Serial Number String: 20170307
Firmware Revision String: V3.9
Hardware Revision String: FD-001-S-N V1.2
Software Revison String: V8.0

There seem to be multiple versions around with different hardware and firmware. Let me know which version you have and if it works.

Configuration
-------------
If you don't have the pimatic-ble plugin add it to the plugin section:

    {
      "plugin": "ble"
    }

Then add the plugin to the plugin section:

    {
      "plugin": "ble-itag"
    },

Then add the device entry for your device into the devices section:

    {
      "id": "itag-keys",
      "class": "ITagDevice",
      "name": "Keys",
      "uuid": "01234567890a",
      "interval": 60000
    }

Then you can add the items into the mobile frontend.

You can also use Discover Devices on the Pimatic Devices screen and your iTag will be automaticly discovered.
