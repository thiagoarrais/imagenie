
###
imagenie: an image hosting service
###

express = require 'express'
db = require('couchdb').createClient(5984, 'localhost').db('images')
im = require 'imagemagick'
crypto = require 'crypto'

AutoBuffer = require './autobuffer'

app = express.createServer()
app.use(express.bodyDecoder())

nonSizes = ['_id', '_rev', 'rev', 'hash']
reservedSizes = nonSizes + ['original']

resize = (imgSource, imgResized, width, height, callback) ->
    stream = im.resize {srcData: imgSource, quality: 0.96, width: width, height: height}
    stream.on 'data', imgResized.write.bind(imgResized)
    stream.on 'end', (err, stderr) -> callback(imgResized.content())

saveResized = (imgSource, origSize, name, size, id, callback) ->
    if origSize.width / origSize.height * size.max_height > size.max_width
        dstHeight = dstWidth = size.max_width
    else
        dstWidth = dstHeight = size.max_height
    resize imgSource, new AutoBuffer(imgSource.length), dstWidth, dstHeight, (imgResized) ->
        retry = (id, name, imgData) ->
            db.getDoc id, (err, doc) ->
                db.saveBufferedAttachment imgData,
                    id, {rev: doc['_rev'], contentType: 'image/jpeg', name: name},
                    (err, att) ->
                        if !err
                            doc.cache ||= {}
                            doc.cache[name] = {width: dstWidth, height: dstHeight}
                            doc['_rev'] = att.rev
                            db.saveDoc id, doc
                        else
                            retry(id, name, imgData) if err.error == 'conflict'
        callback(imgResized) if callback?
        retry id, name, imgResized

cacheSize = (id, name, size, image, response) ->
    imgOriginal = new AutoBuffer(image['_attachments'].original.length)
    stream = db.getStreamingAttachment id, 'original'
    stream.on 'data', (chunk) -> imgOriginal.write(chunk, 'binary')
    stream.on 'end', -> saveResized(imgOriginal.content(), image, name, size, id, (imgResized) ->
        response.writeHead(200, {
            'Content-Length': imgResized.length,
            'Content-Type': 'image/jpeg'})
        response.end(imgResized)
    )

hash_for = (name, rev) ->
    hash = crypto.createHash 'sha1'
    hash.update name
    hash.update String(rev)
    hash.digest 'hex'

app.put '/:album', (req, res) ->
    db.getDoc req.params.album, (err, doc) ->
        if err && 'not_found' != err.error
            res.send "{\"error\" : \"unknown\"}\n", 500
        else if !err && req.query.hash != doc.hash
            res.send "{\"error\" : \"conflict\"}\n", 409
        else
            if req.body
                album = {}
                for own sizeId, size of req.body
                    album[sizeId] = size unless reservedSizes.indexOf(sizeId) != -1
            else
                album = {thumb : {max_height : 120, max_width: 120}}

            album.rev = if doc? then doc.rev + 1 else 1
            album.hash = hash_for req.params.album, album.rev
            album['_rev'] = doc['_rev'] if doc?

            db.saveDoc req.params.album, album, (err, ok) ->
                res.send(JSON.stringify(ok: true, hash: album.hash) + "\n", 201)

app.post '/:album', (req, res) ->
    imgData = new AutoBuffer parseInt(req.headers['content-length'])
    identify = im.identify (err, metadata) ->
        metadata.album = req.params.album
        db.saveDoc metadata, (err, doc) ->
            resize imgData.content(), new AutoBuffer(imgData.length * 2), metadata.width, metadata.height, (imgClean) ->
                db.saveBufferedAttachment imgClean,
                    doc.id, {rev: doc.rev, contentType: 'image/jpeg', name: 'original'},
                    (err) ->
                        db.getDoc req.params.album, (err, album) ->
                            for own k, v of album
                                (saveResized(imgClean, metadata, k, v, doc.id) unless nonSizes.indexOf(k) != -1)
            res.send JSON.stringify({ok: true, id: doc.id}) + "\n", 201

    req.setEncoding 'binary'
    req.on 'data', (chunk) ->
        imgData.write(chunk, 'binary')
        identify.stdin.write(chunk, 'binary')
    req.on 'end', -> identify.stdin.end()

retrieve = (method, album, size, id, res) ->
    db.getDoc id, (err, image) ->
        if err || album != image.album
            res.send 404
        else
            db.getDoc album, (err, album) ->
                if err || 'original' != size && !album[size]
                    console.log 'album does not have this size (' + size + ')?'
                    res.send 404
                else if 'original' != size &&
                    (   !(cached = image.cache[size]) ||
                        cached.height != album[size].height && cached.width != album[size].width)
                            cacheSize id, size, album[size], image, res
                else
                    res.writeHead(200, {
                        'Content-Length': image['_attachments'][size].length,
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
