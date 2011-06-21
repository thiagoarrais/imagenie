
###
imagenie: an image hosting service
###

db = require('couchdb').createClient(5984, 'localhost').db('images')
im = require 'imagemagick'
crypto = require 'crypto'
Orchestra = require 'orchestra'

AutoBuffer = require './autobuffer'
calculateTargetSize = require './target'

internals = ['_id', '_rev']
nonSizes = internals + ['rev', 'hash']
reservedSizes = nonSizes + ['original']

resize = (imgSource, width, height, quality, callback) ->
    imgResized = new AutoBuffer(imgSource.length)
    stream = im.resize {srcData: imgSource, quality: quality, width: width, height: height, strip: false}
    stream.on 'data', imgResized.write.bind(imgResized)
    stream.on 'end', (err, stderr) -> callback(imgResized.content())

saveResized = (imgSource, origInfo, name, size, id, callback) ->
    dstDimensions = calculateTargetSize(origInfo, size)
    resize imgSource, dstDimensions.width, dstDimensions.height, origInfo.quality, (imgResized) ->
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

generateId = (callback) ->
    id = []
    id.push((Math.random() * 0x100000000).toString(16)) for i in [1..4]
    id = id.join('')
    db.getDoc id, (err) ->
        if err && 'not_found' == err.error
            callback(null, id)
        else
            generateId(callback)

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

    orch = new Orchestra()
    generateId orch.emitter('id')
    identify = im.identify orch.emitter('im')
    input.on 'end', orch.emitter('end')

    orch.on 'id,end', (data) -> callback(data.id[0][1])
    orch.on 'id,im', (data) ->
        metadata = data.im[0][1]
        imgDoc =
          album: albumName
          width: metadata.width
          height: metadata.height
          quality: metadata.quality
          datetime: metadata.Properties && metadata.Properties['exif:DateTime']
          model: metadata.Properties && metadata.Properties['exif:Model']
          cache: {}
        db.saveDoc data.id[0][1], imgDoc, (err, doc) ->
            resize imgData.content(), metadata.width, metadata.height, metadata.quality, (imgClean) ->
                db.saveBufferedAttachment imgClean,
                    doc.id, {rev: doc.rev, contentType: 'image/jpeg', name: 'original'},
                    (err) ->
                        db.getDoc albumName, (err, album) ->
                            for own k, v of album
                                (saveResized(imgClean, imgDoc, k, v, doc.id) unless nonSizes.indexOf(k) != -1)

    input.setEncoding 'binary'
    input.on 'data', (chunk) ->
        imgData.write(chunk, 'binary')
        identify.stdin.write(chunk, 'binary')
    orch.on 'end', -> identify.stdin.end()

module.exports.retrieve = (method, album, size, id, res) ->
    db.getDoc id, (err, image) ->
        if err || album != image.album || !image['_attachments']
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

module.exports.info = (method, album, id, res) ->
    db.getDoc id, (err, image) ->
        if err || album != image.album
            res.send 404
        else
            result = JSON.stringify(
                width: image.width
                height: image.height
                datetime: image.datetime
                model: image.model)
            res.writeHead(200, {
                'Content-Length': result.length,
                'Content-Type': 'application/json'})
            if 'GET' == method
                res.write(result)
            res.end()

module.exports.getAlbum = (name, res) ->
    db.getDoc name, (err, album) ->
        if err
            res.send 404
        else
            delete(album[prop]) for prop in internals
            res.writeHead(200, {'Content-Type': 'application/json'})
            res.end(JSON.stringify(album) + "\n")
