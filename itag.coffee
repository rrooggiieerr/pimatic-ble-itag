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
        createCallback: (config) =>
          @addOnScan config.uuid
          new ITagDevice(config)
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
      else
        @devices.splice @devices.indexOf(uuid), 1

  class ITagDevice extends env.devices.Sensor
    attributes:
      battery:
        description: 'State of battery'
        type: 'number'
        unit: '%'
      button:
        description: 'State of button'
        type: 'boolean'
        labels: ['on','off']

    battery: 0.0
    button: false

    constructor: (@config) ->
      @id = @config.id
      @name = @config.name
      @interval = @config.interval
      @uuid = @config.uuid
      @peripheral = null

      super()

      plugin.on('discover-' + @uuid, (peripheral) =>
        env.logger.debug 'Device %s found, state: %s', @name, peripheral.state
        @connect peripheral
      )

    connect: (peripheral) ->
      @peripheral = peripheral
      plugin.removeFromScan @uuid

      @peripheral.on 'disconnect', (error) =>
        env.logger.debug 'Device %s disconnected', @name

      setInterval( =>
        @_connect()
      , @interval)

      @_connect()

    _connect: ->
      if @peripheral.state == 'disconnected'
        plugin.ble.stopScanning()
        @peripheral.connect (error) =>
          if !error
            env.logger.debug 'Device %s connected', @name
            plugin.ble.startScanning()
            @readData @peripheral
          else
            env.logger.debug 'Device %s connection failed: %s', @name, error
      else
        env.logger.debug 'Device %s is still connected', @name

    readData: (peripheral) ->
      env.logger.debug 'readData'
      peripheral.discoverSomeServicesAndCharacteristics null, [], (error, services, characteristics) =>
        characteristics.forEach (characteristic) =>
          switch characteristic.uuid
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
            else
              @logValue characteristic, 'Unknown'

    logValue: (characteristic, desc) ->
      characteristic.read (error, data) =>
        if !error
          if data
            env.logger.debug '(%s) %s: %s', characteristic.uuid, desc, data
        else
          env.logger.debug '(%s) %s: error %s', characteristic.uuid, desc, error

    destroy: ->
      plugin.removeFromScan @uuid
      super()

    getBattery: -> Promise.resolve @battery
    getButton: -> Promise.resolve @button

  plugin = new ITagPlugin
  return plugin
