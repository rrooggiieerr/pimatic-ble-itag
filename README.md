pimatic-itag
=================

Pimatic Plugin that monitors availability of iTag ble devices

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
