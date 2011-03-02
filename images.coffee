
###
imagenie: an image hosting service
###

express = require 'express'
db = require('couchdb').createClient(5984, 'localhost').db('images')
temp = require 'temp'
fs = require 'fs'
im = require 'imagemagick'
http = require 'http'

app = express.createServer()

nonSizes = ['_id', '_rev']

app.put '/:album', (req, res) ->
    db.saveDoc req.params.album, {thumb : {max_height : 120, max_width: 120}}, (err, ok) ->
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
                    db.saveAttachment cleanPath, doc.id, {name : 'clean', contentType: 'image/jpeg', rev : doc.rev}, ->
                        fs.unlink(path)
                        db.getDoc req.params.album, (err, album) ->
                            for k, v of album
                                ((k, v) ->
                                    resizePath = temp.path('')
                                    if metadata.width > metadata.height
                                        dstWidth = v.max_width
                                        dstHeight = 0
                                    else
                                        dstWidth = 0
                                        dstHeight = v.max_height
                                    im.resize {srcPath: cleanPath, dstPath: resizePath, width: dstWidth, height: dstHeight, quality: 0.96}, (err, stdout, stderr) ->
                                        db.getDoc doc.id, (err, doc) ->
                                            db.saveAttachment resizePath, doc['_id'], {name : k, contentType: 'image/jpeg', rev : doc['_rev']}, (err) ->
                                                fs.unlink(resizePath)
                                )(k, v) unless nonSizes.indexOf(k) != -1
                res.send JSON.stringify({ok: true, id: doc.id}) + "\n", 201


app.get '/:album/:id/:size.jpg', (req, res) ->
    db.getDoc req.params.id, (err, doc) ->
        if err || !doc['_attachments'][req.params.size]
            res.send 404
        else
            res.writeHead(200, {
                'Content-Length': doc['_attachments'][req.params.size].length,
                'Content-Type': 'image/jpeg'})
            if 'GET' == req.method
                request = http.createClient(5984).request('GET', '/images/' + doc['_id'] + '/' + req.params.size)
                request.on 'response', (response) ->
                    response.on 'data', (chunk) -> res.write(chunk)
                    response.on 'end', -> res.end()
                request.end()
            else
                res.end()

app.listen 8000
