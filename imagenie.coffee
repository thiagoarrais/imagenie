
###
imagenie: an image hosting service
###

db = require('couchdb').createClient(5984, 'localhost').db('images')
im = require 'imagemagick'
crypto = require 'crypto'

AutoBuffer = require './autobuffer'

internals = ['_id', '_rev']
nonSizes = internals + ['rev', 'hash']
reservedSizes = nonSizes + ['original']

resize = (imgSource, width, height, callback) ->
    imgResized = new AutoBuffer(imgSource.length)
    stream = im.resize {srcData: imgSource, quality: 0.96, width: width, height: height}
    stream.on 'data', imgResized.write.bind(imgResized)
    stream.on 'end', (err, stderr) -> callback(imgResized.content())

calculateTargetSize = (orig, max) ->
    if orig.width / orig.height * max.max_height >= max.max_width
        width : max.max_width
        height : 0
    else
        height : max.max_height
        width : 0

saveResized = (imgSource, origSize, name, size, id, callback) ->
    dstDimensions = calculateTargetSize(origSize, size)
    resize imgSource, dstDimensions.width, dstDimensions.height, (imgResized) ->
        saveAttachment = (id, name, rev, imgData) ->
            db.saveBufferedAttachment imgData,
                id, {rev: rev, contentType: 'image/jpeg', name: name},
                (err) -> if err && 'conflict' == err.error
                    db.getDoc id, (err, doc) -> saveAttachment(id, doc['_rev'], name, imgData)
        updateImage = (id, name, imgData) ->
            db.getDoc id, (err, doc) ->
                doc.cache ||= {}
                doc.cache[name] =
                    max_width: size.max_width, max_height: size.max_height
                    width: dstDimensions.width, height: dstDimensions.height
                db.saveDoc id, doc, (err, status) ->
                    if err
                        updateImage(id, name, imgData) if err.error == 'conflict'
                    else
                        saveAttachment(id, name, status.rev, imgData)
        callback(imgResized) if callback?
        updateImage id, name, imgResized

cacheSize = (id, name, size, image, method, response) ->
    imgOriginal = new AutoBuffer(image['_attachments'].original.length)
    stream = db.getStreamingAttachment id, 'original'
    stream.on 'data', (chunk) -> imgOriginal.write(chunk, 'binary')
    stream.on 'end', -> saveResized(imgOriginal.content(), image, name, size, id, (imgResized) ->
        response.writeHead(200, {
            'Content-Length': imgResized.length,
            'Content-Type': 'image/jpeg'})
        if 'GET' == method
            response.end(imgResized)
        else
            response.end()
    )

hash_for = (name, rev) ->
    hash = crypto.createHash 'sha1'
    hash.update name
    hash.update String(rev)
    hash.digest 'hex'

module.exports.saveAlbum = (name, hash, obj, callback) ->
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

module.exports.saveImage = (albumName, input, callback) ->
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

module.exports.retrieve = (method, album, size, id, res) ->
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
                        !image['_attachments'][size] ||
                            (   cached.max_height != album[size].max_height ||
                                cached.max_width != album[size].max_width) &&
                            (   (target = calculateTargetSize(image, album[size])).height != cached.height ||
                                target.width != cached.width))
                    cacheSize id, size, album[size], image, method, res
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

module.exports.getAlbum = (name, res) ->
    db.getDoc name, (err, album) ->
        if err
            res.send 404
        else
            delete(album[prop]) for prop in internals
            res.writeHead(200, {'Content-Type': 'application/json'})
            res.end(JSON.stringify(album) + "\n")
