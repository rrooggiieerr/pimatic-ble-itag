module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  
  events = require "events"

  class ITagPlugin extends env.plugins.Plugin
    init: (app, @framework, @config) =>
      deviceConfigDef = require("./device-config-schema")
      @devices = []

      @framework.deviceManager.registerDeviceClass("ITagDevice", {
        configDef: deviceConfigDef.ITagDevice,
        createCallback: (config) =>
          @addOnScan config.uuid
          new ITagDevice(config)
      })

      @framework.on "after init", =>
        @ble = @framework.pluginManager.getPlugin 'ble'
        if @ble?
          @ble.registerName 'ITAG'
          (@ble.addOnScan device for device in @devices)
          @ble.on("discover", (peripheral) =>
            @emit "discover-"+peripheral.uuid, peripheral
          )
        else
          env.logger.warn "itag could not find ble. It will not be able to discover devices"

    addOnScan: (uuid) =>
      env.logger.debug "Adding device "+uuid
      if @ble?
        @ble.addOnScan uuid
      else
        @devices.push uuid

    removeFromScan: (uuid) =>
      env.logger.debug "Removing device "+uuid
      if @ble?
        @ble.removeFromScan uuid
      else
        @devices.splice @devices.indexOf(uuid), 1

  class ITagDevice extends env.devices.Sensor
    attributes:
      battery:
        description: "State of battery"
        type: "number"
        unit: '%'
      button:
        description: "State of button"
        type: "boolean"
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
      plugin.on("discover-#{@uuid}", (peripheral) =>
        env.logger.debug 'Device %s found, state: %s', @name, peripheral.state
        if peripheral.state == 'disconnected'
          @connect peripheral
      )

    connect: (peripheral) ->
      if peripheral.state == 'disconnected'
        peripheral.on 'disconnect', =>
          env.logger.debug "Device #{@name} disconnected"
          plugin.addOnScan @uuid

        peripheral.on 'connect', =>
          env.logger.debug "Device #{@name} connected"
          #plugin.removeFromScan @uuid
          #@listenDevice peripheral, this
          @readData peripheral

        peripheral.connect()

      @peripheral = peripheral

    readData: (peripheral) ->
      env.logger.debug 'readData'
      peripheral.discoverSomeServicesAndCharacteristics null, [], (error, services, characteristics) =>
        characteristics.forEach (characteristic) =>
          characteristic.read (error, data) =>
            env.logger.debug 'found characteristic uuid %s but not matched the criteria', characteristic.uuid
            env.logger.debug '%s: %s (%s)', characteristic.uuid, data, error

    destroy: ->
      super()

    getBattery: -> Promise.resolve @battery
    getButton: -> Promise.resolve @button

  plugin = new ITagPlugin
  return plugin
