###
Handy resources:
https://thejeshgn.com/2017/06/20/reverse-engineering-itag-bluetooth-low-energy-button/
###

module.exports = (env) ->
  Promise = env.require 'bluebird'
  
  events = require 'events'

  class ITagPlugin extends env.plugins.Plugin
    init: (app, @framework, @config) =>
      @devices = {}

      deviceConfigDef = require('./device-config-schema')
      @framework.deviceManager.registerDeviceClass('ITagDevice', {
        configDef: deviceConfigDef.ITagDevice,
        createCallback: (config, lastState) =>
          device = new ITagDevice(config, @, lastState)
          @addToScan config.uuid, device
          return device
      })

      @framework.deviceManager.on 'discover', (eventData) =>
          @framework.deviceManager.discoverMessage 'pimatic-itag', 'Scanning for iTags'

          @ble.on 'discover-itag', (peripheral) =>
            env.logger.debug 'Device %s found, state: %s', peripheral.uuid, peripheral.state
            config = {
              class: 'ITagDevice',
              uuid: peripheral.uuid
            }
            @framework.deviceManager.discoveredDevice(
              'pimatic-itag', 'iTag ' + peripheral.uuid, config
            )

      @framework.on 'after init', =>
        @ble = @framework.pluginManager.getPlugin 'ble'
        if @ble?
          @ble.registerName 'ITAG', 'itag'

          for uuid, device of @devices
            @ble.on 'discover-' + uuid, (peripheral) =>
              device = @devices[peripheral.uuid]
              env.logger.debug 'Device %s found, state: %s', device.name, peripheral.state
              #@removeFromScan peripheral.uuid
              device.connect peripheral
            @ble.addToScan uuid, device
        else
          env.logger.warn 'itag could not find ble. It will not be able to discover devices'

    addToScan: (uuid, device) =>
      env.logger.debug 'Adding device %s', uuid
      if @ble?
        @ble.on 'discover-' + uuid, (peripheral) =>
          device = @devices[peripheral.uuid]
          env.logger.debug 'Device %s found, state: %s', device.name, peripheral.state
          #@removeFromScan peripheral.uuid
          device.connect peripheral
        @ble.addToScan uuid, device
      @devices[uuid] = device

    removeFromScan: (uuid) =>
      env.logger.debug 'Removing device %s', uuid
      if @ble?
        @ble.removeFromScan uuid
      if @devices[uuid]
        delete @devices[uuid]

  class ITagDevice extends env.devices.PresenceSensor
    attributes:
      #battery:
      #  description: 'State of battery'
      #  type: 'number'
      #  unit: '%'
      button:
        description: 'State of button'
        type: 'boolean'
        labels: ['on','off']
      presence:
        description: 'Presence of the iTag device'
        type: 'boolean'
        labels: ['present', 'absent']

    actions:
      buzzer:
        description: 'Buzzer sound: off, low, high'
        params:
          state:
            type: 'string'

    template: 'presence'

    #battery: 0.0
    button: false

    constructor: (@config, plugin, lastState) ->
      @id = @config.id
      @name = @config.name
      @interval = @config.interval
      @uuid = @config.uuid
      @linkLossAlert = @config.linkLossAlert
      @peripheral = null
      @plugin = plugin

      @_presence = false
      #@_presence = lastState?.presence?.value or false

      super()

    connect: (peripheral) ->
      @peripheral = peripheral

      @peripheral.on 'disconnect', (error) =>
        env.logger.debug 'Device %s disconnected', @name
        @_setPresence false

        clearInterval @reconnectInterval
        if @_destroyed then return
        @reconnectInterval = setInterval( =>
          @_connect()
        , @interval)
        # Immediately try to reconnect
        @_connect()

      @reconnectInterval = setInterval( =>
        @_connect()
      , @interval)
      @_connect()

    _connect: ->
      if @_destroyed then return
      if @peripheral.state == 'disconnected'
        env.logger.debug 'Trying to connect to %s', @name
        @plugin.ble.stopScanning()
        @peripheral.connect (error) =>
          if !error
            env.logger.debug 'Device %s connected', @name
            @_setPresence true
            @readData @peripheral
            clearInterval @reconnectInterval
          else
            env.logger.debug 'Device %s connection failed: %s', @name, error
            @_setPresence false
          @plugin.ble.startScanning()

    readData: (peripheral) ->
      env.logger.debug 'Reading data from %s', @name

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
              @logValue peripheral, characteristic, 'Model Number'
            when '2a25'
              @logValue peripheral, characteristic, 'Serial Number'
            when '2a26'
              @logValue peripheral, characteristic, 'Firmware Revision'
            when '2a27'
              @logValue peripheral, characteristic, 'Hardware Revision'
            when '2a28'
              @logValue peripheral, characteristic, 'Software Revision'
            when '2a29'
              @logValue peripheral, characteristic, 'Manufacturer Name'
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
              @logValue peripheral, characteristic, 'Unknown'

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

    logValue: (peripheral, characteristic, desc) ->
      characteristic.read (error, data) =>
        if !error
          if data
            env.logger.debug '(%s:%s) %s: %s', peripheral.uuid, characteristic.uuid, desc, data
        else
          env.logger.debug '(%%s:s) %s: error %s', peripheral.uuid, characteristic.uuid, desc, error

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
      env.logger.debug 'Destroy %s', @name
      @_destroyed = true
      @emit('destroy', @)
      @removeAllListeners('destroy')
      @removeAllListeners(attrName) for attrName of @attributes

      if @peripheral && @peripheral.state == 'connected'
        @peripheral.disconnect()
      @plugin.removeFromScan @uuid
      super()

    #getBattery: -> Promise.resolve @battery
    getButton: -> Promise.resolve @button

  return new ITagPlugin
