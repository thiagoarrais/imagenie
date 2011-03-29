
###
imagenie: an image hosting service
###

express = require 'express'
db = require('couchdb').createClient(5984, 'localhost').db('images')
fs = require 'fs'
child = require 'child_process'
http = require 'http'
async = require 'async'
im = require 'imagemagick'

app = express.createServer()
app.use(express.bodyDecoder())

nonSizes = ['_id', '_rev']
reservedSizes = nonSizes + ['original']

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
    this.buffer.write(data, this.length, encoding)
    this.length += data.length

client = null
resize = (imgSource, origSize, name, size, id) ->
    if origSize.width > origSize.height
        dstHeight = dstWidth = size.max_width
    else
        dstWidth = dstHeight = size.max_height
    imgResized = new AutoBuffer(imgSource.length)
    im.resize {srcData: imgSource, destination: imgResized, quality: 0.96, width: dstWidth, height: dstHeight}, (err, stderr) ->
        retry = (id, name, imgData) ->
            db.getDoc id, (err, doc) ->
                client ||= http.createClient(5984)
                req = client.request 'PUT', '/images/'+id+'/'+name+'?rev='+doc['_rev'], {'Content-Type' : 'image/jpeg', 'Content-Length' : imgData.length}
                req.on 'response', (response) ->
                    retry(id, name, imgData) if response.statusCode == 409
                req.end imgData
        retry id, name, imgResized.content()

app.put '/:album', (req, res) ->
    if req.body
        album = {}
        for own sizeId, size of req.body
            album[sizeId] = size unless reservedSizes.indexOf(sizeId) != -1
    else
        album = {thumb : {max_height : 120, max_width: 120}}

    db.saveDoc req.params.album, album, (err, ok) ->
        res.send "{\"ok\": true}\n", 201

app.post '/:album', (req, res) ->
    imgData = new AutoBuffer parseInt(req.headers['content-length'])
    identify = im.identify (err, metadata) ->
        metadata.album = req.params.album
        db.saveDoc metadata, (err, doc) ->
            imgClean = new AutoBuffer(imgData.length * 2)
            im.resize {srcData: imgData.content(), destination: imgClean, quality: 0.96, width: metadata.width, height: metadata.height}, (err, stderr) ->
                request = http.createClient(5984).request('PUT', '/images/' + doc.id + '/original?rev=' + doc.rev, {'Content-Type' : 'image/jpg', 'Content-Length': imgClean.length})
                request.on 'response', ->
                    db.getDoc req.params.album, (err, album) ->
                        (resize(imgClean.content(), metadata, k, v, doc.id) unless nonSizes.indexOf(k) != -1) for own k, v of album
                request.end imgClean.content()
            res.send JSON.stringify({ok: true, id: doc.id}) + "\n", 201

    req.setEncoding 'binary'
    req.on 'data', (chunk) ->
        imgData.write(chunk, 'binary')
        identify.stdin.write(chunk, 'binary')
    req.on 'end', -> identify.stdin.end()

retrieve = (method, album, size, id, res) ->
    db.getDoc id, (err, doc) ->
        if err || !doc['_attachments'][size] || album != doc.album
            res.send 404
        else
            res.writeHead(200, {
                'Content-Length': doc['_attachments'][size].length,
                'Content-Type': 'image/jpeg'})
            if 'GET' == method
                request = http.createClient(5984).request('GET', '/images/' + doc['_id'] + '/' + size)
                request.on 'response', (response) ->
                    response.on 'data', (chunk) -> res.write(chunk)
                    response.on 'end', -> res.end()
                request.end()
            else
                res.end()

app.get '/:album/:id.jpg', (req, res) -> retrieve(req.method, req.params.album, 'original', req.params.id, res)
app.get '/:album/:size/:id.jpg', (req, res) -> retrieve(req.method, req.params.album, req.params.size, req.params.id, res)

app.listen 8000
