
###
Wrapper around node's Buffer type with automatic growth
###

AutoBuffer = (size) ->
    this.buffer = new Buffer(size)
    this.length = 0
    this.capacity = size

AutoBuffer.prototype.content = ->
    this.buffer.slice(0, this.length)

AutoBuffer.prototype.end = ->
    this.buffer = this.content()

AutoBuffer.prototype.write = (data, encoding) ->
    if this.length + data.length > this.capacity
        old = this.buffer
        this.capacity *= 2
        this.buffer = new Buffer(this.capacity)
        old.copy(this.buffer, 0, 0, this.length)
    if Buffer.isBuffer(data)
        data.copy(this.buffer, this.length)
    else
        this.buffer.write(data, this.length, encoding)
    this.length += data.length

module.exports = AutoBuffer

