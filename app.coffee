
###
imagenie: an image hosting service
###

express = require 'express'
db = require('couchdb').createClient(5984, 'localhost').db('images')
im = require 'imagemagick'
AutoBuffer = require './autobuffer'

app = express.createServer()
app.use(express.bodyDecoder())

nonSizes = ['_id', '_rev']
reservedSizes = nonSizes + ['original']

resize = (imgSource, imgResized, width, height, callback) ->
    stream = im.resize {srcData: imgSource, quality: 0.96, width: width, height: height}
    stream.on 'data', imgResized.write.bind(imgResized)
    stream.on 'end', (err, stderr) -> callback(imgResized.content())

saveResized = (imgSource, origSize, name, size, id) ->
    if origSize.width > origSize.height
        dstHeight = dstWidth = size.max_width
    else
        dstWidth = dstHeight = size.max_height
    resize imgSource, new AutoBuffer(imgSource.length), dstWidth, dstHeight, (imgResized) ->
        retry = (id, name, imgData) ->
            db.getDoc id, (err, doc) ->
                db.saveBufferedAttachment imgData, id, {rev: doc['_rev'], contentType: 'image/jpeg', name: name}, (err) ->
                    retry(id, name, imgData) if err && err.error == 'conflict'
        retry id, name, imgResized

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
            resize imgData.content(), new AutoBuffer(imgData.length * 2), metadata.width, metadata.height, (imgClean) ->
                db.saveBufferedAttachment imgClean, doc.id, {rev: doc.rev, contentType: 'image/jpeg', name: 'original'}, (err) ->
                    db.getDoc req.params.album, (err, album) ->
                        (saveResized(imgClean, metadata, k, v, doc.id) unless nonSizes.indexOf(k) != -1) for own k, v of album
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
                stream = db.getStreamingAttachment id, size
                stream.on 'data', (chunk) -> res.write(chunk, 'binary')
                stream.on 'end', -> res.end()
            else
                res.end()

app.get '/:album/:id.jpg', (req, res) -> retrieve(req.method, req.params.album, 'original', req.params.id, res)
app.get '/:album/:size/:id.jpg', (req, res) -> retrieve(req.method, req.params.album, req.params.size, req.params.id, res)

app.listen 8000
