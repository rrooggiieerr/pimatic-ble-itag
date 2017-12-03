module.exports = {
  title: "pimatic-itag device config schemas"
  ITagDevice: {
    title: "iTag config options"
    type: "object"
    extensions: ["xLink", "xAttributeOptions"]
    properties:
      uuid:
        description: "uuid of the iTag to connect"
        type: "string"
      interval:
        description: "Interval between reconnects"
        type: "number"
        default: 10000
      linkLossAlert:
        description: "Alert to make when link with iTag is lost: no, mild, high"
        type: "string"
        default: "off"
  }
}
