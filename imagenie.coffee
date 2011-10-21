
###
imagenie: an image hosting service
###

im = require 'imagemagick'
crypto = require 'crypto'
Orchestra = require 'orchestra'

AutoBuffer = require './autobuffer'
calculateTargetSize = require './target'
withDB = require './with_db'

internals = ['_id', '_rev']
nonSizes = internals + ['rev', 'hash']
reservedSizes = nonSizes + ['original']

resize = (imgSource, width, height, format, quality, callback) ->
    imgResized = new AutoBuffer(imgSource.length)
    opts = {srcData: imgSource, format: format, width: width, height: height, strip: false}
    opts.quality = quality if quality
    stream = if 0 == width || 0 == height
        im.resize opts
    else
        im.crop opts
    stream.on 'data', (chunk) -> imgResized.write(chunk, 'binary')
    stream.on 'end', (err, stderr) -> callback(imgResized.content())

saveResized = (imgSource, origInfo, name, size, mimetype, id, callback) ->
    dstDimensions = calculateTargetSize(origInfo, size)
    resize imgSource, dstDimensions.width, dstDimensions.height, origInfo.format.toLowerCase(), origInfo.quality, (imgResized) ->
        saveAttachment = (id, name, rev, imgData) -> withDB (db) ->
            db.attachment.insert id, name, imgData, mimetype, {rev: rev},
                (err) -> if err && 'conflict' == err.error
                    db.get id, (_, doc) -> saveAttachment(id, doc['_rev'], name, imgData)
        updateImage = (id, name, imgData) -> withDB (db) ->
            db.get id, (_, doc) ->
                doc.cache ||= {}
                doc.cache[name] =
                    max_width: size.max_width, max_height: size.max_height
                    width: dstDimensions.width, height: dstDimensions.height
                db.insert doc, id, (err, status) ->
                    if err
                        updateImage(id, name, imgData) if err.error == 'conflict'
                    else
                        saveAttachment(id, name, status.rev, imgData)
        callback(imgResized) if callback?
        updateImage id, name, imgResized

cacheSize = (id, name, size, image, method, response) -> withDB (db) ->
    imgOriginal = new AutoBuffer(image['_attachments'].original.length)
    stream = db.attachment.get id, 'original'
    stream.on 'data', (chunk) -> imgOriginal.write(chunk)
    stream.on 'end', -> saveResized(imgOriginal.content(), image, name, size, image['_attachments'][size].content_type, id, (imgResized) ->
        response.writeHead(200, {
            'Content-Length': imgResized.length,
            'Content-Type': image['_attachments'][size].content_type })
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

generateId = (callback) -> withDB (db) ->
    id = []
    id.push((Math.random() * 0x100000000).toString(16)) for i in [1..4]
    id = id.join('')
    db.get id, (err) ->
        if err && 'not_found' == err.error
            callback(null, id)
        else
            generateId(callback)

module.exports.saveAlbum = (name, hash, obj, callback) -> withDB (db) ->
    db.get name, (err, doc) ->
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

            album.rev = if err && 'not_found' == err.error then 1 else doc.rev + 1
            album.hash = hash_for name, album.rev
            album['_rev'] = doc['_rev'] if doc?

            db.insert album, name, (err) ->
                callback(ok: true, hash: album.hash)

module.exports.saveImage = (albumName, input, callback) ->
    imgData = new AutoBuffer 1024 * 256

    orch = new Orchestra()
    generateId orch.emitter('id')
    identify = im.identify orch.emitter('im')

    orch.on 'id,im', (data) -> withDB (db) ->
        metadata = data.im[0][1]
        format = metadata.format.toLowerCase()
        imgDoc =
          format: format
          album: albumName
          width: metadata.width
          height: metadata.height
          quality: metadata.quality
          datetime: metadata.Properties && metadata.Properties['exif:DateTime']
          model: metadata.Properties && metadata.Properties['exif:Model']
          cache: {}
        mimetype = 'image/' + format
        id = data.id[0][1]
        callback id
        db.insert imgDoc, id, (err, doc) ->
            resize imgData.content(), metadata.width, metadata.height, format, metadata.quality, (imgClean) ->
                db.attachment.insert doc.id, 'original', imgClean, mimetype, {rev: doc.rev},
                    (err) ->
                        db.get albumName, (err, album) ->
                            for own k, v of album
                                (saveResized(imgClean, imgDoc, k, v, mimetype, doc.id) unless nonSizes.indexOf(k) != -1)

    input.setEncoding 'binary'
    input.on 'data', (chunk) ->
        imgData.write(chunk, 'binary')
        identify.write(chunk, 'binary')
    input.on 'end', -> identify.end()

geometryEquals = (a, b) -> a.width == b.width && a.height == b.height

module.exports.retrieve = (method, album, size, id, res) -> withDB (db) ->
    db.get id, (err, image) ->
        if err || album != image.album || !image['_attachments']
            res.send 404
        else
            db.get album, (err, album) ->
                if err || 'original' != size && !album[size]
                    console.log 'album does not have this size (' + size + ')?'
                    res.send 404
                else if 'original' != size &&
                    (   !(cached = image.cache[size]) ||
                        !image['_attachments'][size] ||
                        !geometryEquals(cached, calculateTargetSize(image, album[size])))
                    cacheSize id, size, album[size], image, method, res
                else
                    res.writeHead(200, {
                        'Content-Length': image['_attachments'][size].length,
                        'Content-Type': image['_attachments'][size].content_type })
                    if 'GET' == method
                        stream = db.attachment.get id, size
                        stream.on 'data', (chunk) -> res.write(chunk, 'binary')
                        stream.on 'end', -> res.end()
                    else
                        res.end()

module.exports.info = (method, album, id, res) -> withDB (db) ->
    db.get id, (err, image) ->
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

module.exports.getAlbum = (name, res) -> withDB (db) ->
    db.get name, (err, album) ->
        if err
            res.send 404
        else
            delete(album[prop]) for prop in internals
            res.writeHead(200, {'Content-Type': 'application/json'})
            res.end(JSON.stringify(album) + "\n")

