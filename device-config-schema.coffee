module.exports ={
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
        description: "Interval between requests"
        type: "number"
        default: 60000
  }
}
