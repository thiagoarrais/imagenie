
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

internals = ['_id', '_rev']
nonSizes = internals + ['rev', 'hash']
reservedSizes = nonSizes + ['original']

resize = (imgSource, width, height, callback) ->
    imgResized = new AutoBuffer(imgSource.length)
    stream = im.resize {srcData: imgSource, quality: 0.96, width: width, height: height}
    stream.on 'data', imgResized.write.bind(imgResized)
    stream.on 'end', (err, stderr) -> callback(imgResized.content())

saveResized = (imgSource, origSize, name, size, id, callback) ->
    if origSize.width / origSize.height * size.max_height > size.max_width
        dstHeight = dstWidth = size.max_width
    else
        dstWidth = dstHeight = size.max_height
    resize imgSource, dstWidth, dstHeight, (imgResized) ->
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

saveAlbum = (name, hash, obj, callback) ->
    db.getDoc name, (err, doc) ->
        if err && 'not_found' != err.error
            callback(error: 'unknown')
        else if !err && hash != doc.hash
            callback(error: 'conflict')
        else
            if obj
                album = {}
                for own sizeId, size of obj
                    album[sizeId] = size unless reservedSizes.indexOf(sizeId) != -1
            else
                album = {thumb : {max_height : 120, max_width: 120}}

            album.rev = if doc? then doc.rev + 1 else 1
            album.hash = hash_for name, album.rev
            album['_rev'] = doc['_rev'] if doc?

            db.saveDoc name, album, (err, ok) ->
                callback(ok: true, hash: album.hash)

saveImage = (albumName, input, callback) ->
    imgData = new AutoBuffer 1024 * 256
    identify = im.identify (err, metadata) ->
        metadata.album = albumName
        db.saveDoc metadata, (err, doc) ->
            resize imgData.content(), metadata.width, metadata.height, (imgClean) ->
                db.saveBufferedAttachment imgClean,
                    doc.id, {rev: doc.rev, contentType: 'image/jpeg', name: 'original'},
                    (err) ->
                        db.getDoc albumName, (err, album) ->
                            for own k, v of album
                                (saveResized(imgClean, metadata, k, v, doc.id) unless nonSizes.indexOf(k) != -1)
            callback(doc.id)

    input.setEncoding 'binary'
    input.on 'data', (chunk) ->
        imgData.write(chunk, 'binary')
        identify.stdin.write(chunk, 'binary')
    input.on 'end', -> identify.stdin.end()

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

getAlbum = (name, callback) ->
    db.getDoc name, (err, album) ->
        delete(album[prop]) for prop in internals
        callback(album)

error_codes =
    undefined: 201
    'conflict': 409
    'unknown': 500

app.put '/:album', (req, res) ->
    saveAlbum req.params.album, req.query.hash, req.body, (result) ->
        res.send(JSON.stringify(result) + "\n", error_codes[result.error])

app.post '/:album', (req, res) ->
    saveImage req.params.album, req, (id) -> res.send JSON.stringify({ok: true, id: id}) + "\n", 201

app.get '/:album', (req, res) ->
    getAlbum req.params.album, (album) ->
        res.writeHead(200, {'Content-Type': 'application/json'})
        res.end(JSON.stringify(album) + "\n")

app.get '/:album/:id.jpg', (req, res) -> retrieve(req.method, req.params.album, 'original', req.params.id, res)
app.get '/:album/:size/:id.jpg', (req, res) -> retrieve(req.method, req.params.album, req.params.size, req.params.id, res)

app.listen 8000
