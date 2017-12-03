###
Handy resources:
https://thejeshgn.com/2017/06/20/reverse-engineering-itag-bluetooth-low-energy-button/
###

module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  
  events = require 'events'

  class ITagPlugin extends env.plugins.Plugin
    init: (app, @framework, @config) =>
      deviceConfigDef = require('./device-config-schema')
      @devices = []

      @framework.deviceManager.registerDeviceClass('ITagDevice', {
        configDef: deviceConfigDef.ITagDevice,
        createCallback: (config, lastState) =>
          @addOnScan config.uuid
          new ITagDevice(config, @, lastState)
      })

      @framework.on 'after init', =>
        @ble = @framework.pluginManager.getPlugin 'ble'
        if @ble?
          @ble.registerName 'ITAG'

          @ble.addOnScan device for device in @devices

          @ble.on('discover', (peripheral) =>
            @emit 'discover-' + peripheral.uuid, peripheral
          )
        else
          env.logger.warn 'itag could not find ble. It will not be able to discover devices'

    addOnScan: (uuid) =>
      env.logger.debug 'Adding device ' + uuid
      if @ble?
        @ble.addOnScan uuid
      else
        @devices.push uuid

    removeFromScan: (uuid) =>
      env.logger.debug 'Removing device %s', uuid
      if @ble?
        @ble.removeFromScan uuid
      if uuid in @devices
        @devices.splice @devices.indexOf(uuid), 1

  class ITagDevice extends env.devices.PresenceSensor
    attributes:
      battery:
        description: 'State of battery'
        type: 'number'
        unit: '%'
      button:
        description: 'State of button'
        type: 'boolean'
        labels: ['on','off']
      presence:
        description: "Presence of the iTag device"
        type: 'boolean'
        labels: ['present', 'absent']

    actions:
      buzzer:
        description: 'Buzzer sound: off, low, high'
        params:
          state:
            type: 'string'

    template: 'presence'

    battery: 0.0
    button: false

    constructor: (@config, plugin, lastState) ->
      @id = @config.id
      @name = @config.name
      @interval = @config.interval
      @uuid = @config.uuid
      @linkLossAlert = @config.linkLossAlert
      @peripheral = null
      @plugin = plugin

      @_presence = lastState?.presence?.value or false

      super()

      @plugin.on('discover-' + @uuid, (peripheral) =>
        env.logger.debug 'Device %s found, state: %s', @name, peripheral.state
        @connect peripheral
      )

    connect: (peripheral) ->
      @peripheral = peripheral
      @plugin.removeFromScan @uuid

      @peripheral.on 'disconnect', (error) =>
        env.logger.debug 'Device %s disconnected', @name
        @_setPresence false
        # Immediately try to reconnect
        @_connect()

      setInterval( =>
        @_connect()
      , @interval)

      @_connect()

    _connect: ->
      if @peripheral.state == 'disconnected'
        @plugin.ble.stopScanning()
        @peripheral.connect (error) =>
          if !error
            env.logger.debug 'Device %s connected', @name
            @plugin.ble.startScanning()
            @_setPresence true
            @readData @peripheral
          else
            env.logger.debug 'Device %s connection failed: %s', @name, error
            @_setPresence false

    readData: (peripheral) ->
      env.logger.debug 'readData'

      #peripheral.discoverServices null, (error, services) =>
      #  env.logger.debug 'Services: %s', services
      # {"uuid":"180a","name":"Device Information","type":"org.bluetooth.service.device_information","includedServiceUuids":null},{"uuid":"1802","name":"Immediate Alert","type":"org.bluetooth.service.immediate_alert","includedServiceUuids":null},{"uuid":"1803","name":"Link Loss","type":"org.bluetooth.service.link_loss","includedServiceUuids":null},{"uuid":"ffe0","name":null,"type":null,"includedServiceUuids":null}
        
      peripheral.discoverSomeServicesAndCharacteristics ['180a', '0803', 'ffe0'], [], (error, services, characteristics) =>
        characteristics.forEach (characteristic) =>
          switch characteristic.uuid
            when '2a06'
              # Link Loss
              switch @linkLossAlert
                when 'no'
                  characteristic.write Buffer.from([0x01]), 0
                when 'mild'
                  characteristic.write Buffer.from([0x01]), 1
                when 'high'
                  characteristic.write Buffer.from([0x01]), 2
            when '2a24'
              @logValue characteristic, 'Model Number'
            when '2a25'
              @logValue characteristic, 'Serial Number'
            when '2a26'
              @logValue characteristic, 'Firmware Revision'
            when '2a27'
              @logValue characteristic, 'Hardware Revision'
            when '2a28'
              @logValue characteristic, 'Software Revision'
            when '2a29'
              @logValue characteristic, 'Manufacturer Name'
            when 'ffe1'
              characteristic.on 'data', (data, isNotification) =>
                env.logger.debug 'Button pressed'
                @button = true
                @emit 'button', @button
                setTimeout =>
                  @button = false
                  @emit 'button', @button
                , 500
              #characteristic.subscribe (error) =>
              #  env.logger.debug 'Button notifier on'
            else
              @logValue characteristic, 'Unknown'

      ###
      peripheral.discoverSomeServicesAndCharacteristics ['1802'], [], (error, services, characteristics) =>
        characteristics.forEach (characteristic) =>
          switch characteristic.uuid
            when '2a06'
              # Alarm signal
              characteristic.write Buffer.from([0x01]), 0

      peripheral.discoverSomeServicesAndCharacteristics ['1803'], [], (error, services, characteristics) =>
        characteristics.forEach (characteristic) =>
          switch characteristic.uuid
            when '2a06'
              # Out of reach signal
              characteristic.write Buffer.from([0x01]), 0

      peripheral.discoverSomeServicesAndCharacteristics ['ffe0'], [], (error, services, characteristics) =>
        characteristics.forEach (characteristic) =>
          switch characteristic.uuid
            when 'ffe1'
              characteristic.on 'data', (data, isNotification) =>
                env.logger.debug 'Button pressed'
                @button = true
                @emit 'button', @button
                setTimeout =>
                  @button = false
                  @emit 'button', @button
                , 500
              #characteristic.subscribe (error) =>
              #  env.logger.debug 'Button notifier on'
      ###

    logValue: (characteristic, desc) ->
      characteristic.read (error, data) =>
        if !error
          if data
            env.logger.debug '(%s) %s: %s', characteristic.uuid, desc, data
        else
          env.logger.debug '(%s) %s: error %s', characteristic.uuid, desc, error

    buzzer: (level) ->
      if @peripheral.state == 'disconnected'
        throw new Error('Device disconnected')
        return

    #  switch level
    #    when 'no'
    #    when 'mild'
    #    when 'high'
    #    else
    #      throw new Error('Invallid level, use no, mild or high')

    destroy: ->
      @plugin.removeFromScan @uuid
      super()

    getBattery: -> Promise.resolve @battery
    getButton: -> Promise.resolve @button

  return new ITagPlugin
