pimatic-itag
=================

Pimatic Plugin that monitors availability of iTag ble devices

I'm working with this device:
Settings in the BT firmware:
Manufacturer Name String: 3231S FDQ
Model Number String: BT 4.0
Serial Number String: 20170307
Firmware Revision String: V3.9
Hardware Revision String: FD-001-S-N V1.2
Software Revison String: V8.0

On the device:
Serial Number String: 20170414
Hardware Revision String: FD-001-S-N V1.5

Configuration
-------------
If you don't have the pimatic-ble plugin add it to the plugin section:

    {
      "plugin": "ble"
    }

Then add the plugin to the plugin section:

    {
      "plugin": "itag"
    },

Then add the device entry for your device into the devices section:

    {
      "id": "itag-keys",
      "class": "ITagDevice",
      "name": "Keys",
      "uuid": "01234567890a",
      "interval": 60000
    }

Then you can add the items into the mobile frontend
# pimatic-itag
