###
Handy resources:
https://thejeshgn.com/2017/06/20/reverse-engineering-itag-bluetooth-low-energy-button/
###

module.exports = (env) ->
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  _ = require 'lodash' 
  M = env.matcher

  class ITagPlugin extends env.plugins.Plugin
    init: (app, @framework, @config) =>
      @devices = {}

      @framework.ruleManager.addActionProvider(new ITagBuzzerActionProvider(@framework))

      deviceConfigDef = require('./device-config-schema')
      @framework.deviceManager.registerDeviceClass('ITagDevice', {
        configDef: deviceConfigDef.ITagDevice,
        createCallback: (config, lastState) =>
          device = new ITagDevice(config, @, lastState)
          @addToScan config.uuid, device
          return device
      })

      @framework.deviceManager.on 'discover', (eventData) =>
          @framework.deviceManager.discoverMessage 'pimatic-ble-itag', 'Scanning for iTags'

          @ble.on 'discover-itag', (peripheral) =>
            env.logger.debug 'Device %s found, state: %s', peripheral.uuid, peripheral.state
            config = {
              class: 'ITagDevice',
              uuid: peripheral.uuid
            }
            @framework.deviceManager.discoveredDevice(
              'pimatic-ble-itag', 'iTag ' + peripheral.uuid, config
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

  class ITagDevice extends env.devices.BLEDevice
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

    #_battery: 0.0
    _button: false

    constructor: (@config, @plugin, lastState) ->
      @linkLossAlert = @config.linkLossAlert

      super(@config, @plugin, lastState)

    onDisconnect: () ->
      @_setPresence false
      # Immediately try to reconnect
      @_connect()

    readData: (peripheral) ->
      env.logger.debug 'Reading data from %s', @name

      #peripheral.discoverServices null, (error, services) =>
      #  env.logger.debug 'Services: %s', services
      # {"uuid":"180a","name":"Device Information","type":"org.bluetooth.service.device_information","includedServiceUuids":null},{"uuid":"1802","name":"Immediate Alert","type":"org.bluetooth.service.immediate_alert","includedServiceUuids":null},{"uuid":"1803","name":"Link Loss","type":"org.bluetooth.service.link_loss","includedServiceUuids":null},{"uuid":"ffe0","name":null,"type":null,"includedServiceUuids":null}
        
      peripheral.discoverSomeServicesAndCharacteristics ['180a', '1803', 'ffe0'], [], (error, services, characteristics) =>
        characteristics.forEach (characteristic) =>
          switch characteristic.uuid
            #when '2a06'
              # Link Loss
              # This does not yet seem to work, just put it off for now
              #env.logger.debug 'Setting Link Loss alert to 0x00'
              #characteristic.write Buffer.from([0x02]), 0x00
              #switch @linkLossAlert
              #  when 'off'
              #    characteristic.write Buffer.from([0x01]), 0x00
              #  when 'low'
              #    characteristic.write Buffer.from([0x01]), 0x01
              #  when 'high'
              #    characteristic.write Buffer.from([0x01]), 0x02
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
                @_button = true
                @emit 'button', @_button
                setTimeout =>
                  @_button = false
                  @emit 'button', @_button
                , 500
              #characteristic.subscribe (error) =>
              #  env.logger.debug 'Button notifier on'
            else
              @logValue peripheral, characteristic, 'Unknown'

    logValue: (peripheral, characteristic, desc) ->
      characteristic.read (error, data) =>
        if !error
          if data
            env.logger.debug '(%s:%s) %s: %s', peripheral.uuid, characteristic.uuid, desc, data
        else
          env.logger.debug '(%%s:s) %s: error %s', peripheral.uuid, characteristic.uuid, desc, error

    buzzer: (level) ->
      if !@peripheral || @peripheral.state == 'disconnected'
        throw new Error('Device disconnected')
        return
      env.logger.debug 'Buzzer %s', level
      @peripheral.discoverSomeServicesAndCharacteristics ['1802'], ['2a06'], (error, services, characteristics) =>
        characteristics.forEach (characteristic) =>
          env.logger.debug characteristic.uuid
          switch characteristic.uuid
            when '2a06'
              @logValue @peripheral, characteristic, 'Alert Level'
              # This does not yet seem to work, just put it off for now
              characteristic.write Buffer.from([0x01]), false
              #switch level
              #  when 'off'
              #    characteristic.write Buffer.from([0x01]), 0x00
              #  when 'low'
              #    characteristic.write Buffer.from([0x01]), 0x01
              #  when 'high'
              #    characteristic.write Buffer.from([0x01]), 0x02

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

    #getBattery: -> Promise.resolve @_battery
    getButton: -> Promise.resolve @_button

  class ITagBuzzerActionProvider extends env.actions.ActionProvider
    constructor: (@framework, @plugin) ->

    executeAction: (simulate) =>

    parseAction: (input, context) =>
      buzzerDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => device.hasAction('buzzer')
      ).value()

      device = null
      state = null
      match = null

      m = M(input, context)
        .match(['turn ', 'switch '])
        .matchDevice(buzzerDevices, (m, _device) ->
          m.match(' buzzer ')
            .match(['off', 'low', 'high'], (m, _state) ->
              device = _device
              state = _state
              match =  m.getFullMatch()
            )
        )

      if match?
        assert device?
        assert state in ['off', 'low', 'high']
        assert typeof match is "string"
        return {
          token: match
          nextInput: input.substring match.length
          actionHandler: new ITagBuzzerActionHandler device, state
        }
      return null
      
  class ITagBuzzerActionHandler extends env.actions.ActionHandler
    constructor: (@device, @state) ->

    setup: ->
      @dependOnDevice(@device)
      super()

    _doExecuteAction: (simulate, state) =>
      return (
        if simulate
          Promise.resolve __('would switch %s buzzer %s', @device.name, @state)
        else
          @device.buzzer @state
          Promise.resolve __('switched %s buzzer %s', @device.name, @state)
      )

    executeAction: (simulate) => @_doExecuteAction simulate, @state

  return new ITagPlugin
