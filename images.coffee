
###
imagenie: an image hosting service
###

express = require 'express'
db = require('couchdb').createClient(5984, 'localhost').db('images')
temp = require 'temp'
fs = require 'fs'
im = require 'imagemagick'
http = require 'http'
async = require 'async'

app = express.createServer()
app.use(express.bodyDecoder())

nonSizes = ['_id', '_rev']
reservedSizes = nonSizes + ['original']

resizeTask = (origPath, origSize, name, size, id) -> (callback) ->
    resizePath = temp.path('')
    if origSize.width > origSize.height
        dstWidth = size.max_width
        dstHeight = 0
    else
        dstWidth = 0
        dstHeight = size.max_height
    im.resize {srcPath: origPath, dstPath: resizePath, width: dstWidth, height: dstHeight, quality: 0.96}, (err, stdout, stderr) ->
        db.getDoc id, (err, doc) ->
            db.saveAttachment resizePath, id, {name : name, contentType: 'image/jpeg', rev : doc['_rev']}, (err) ->
                fs.unlink(resizePath)
                callback(null, name)

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
    path = temp.path('')
    output = fs.createWriteStream(path)
    req.on 'data', (chunk) -> output.write(chunk)
    req.on 'end', ->
        output.end()
        im.identify path, (err, metadata) ->
            metadata['album'] = req.params.album
            db.saveDoc metadata, (err, doc) ->
                cleanPath = temp.path('')
                im.resize {srcPath : path, dstPath: cleanPath, width: metadata.width, height: metadata.height, quality: 0.96}, (err, stdout, stderr) ->
                    db.saveAttachment cleanPath, doc.id, {name : 'original', contentType: 'image/jpeg', rev : doc.rev}, ->
                        fs.unlink(path)
                        db.getDoc req.params.album, (err, album) ->
                            tasks = []
                            (tasks.push(resizeTask(cleanPath, metadata, k, v, doc.id)) unless nonSizes.indexOf(k) != -1) for own k, v of album
                            async.parallel tasks, (err, results) -> fs.unlink(cleanPath) unless err
                res.send JSON.stringify({ok: true, id: doc.id}) + "\n", 201


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
