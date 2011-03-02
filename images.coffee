
###
imagenie: an image hosting service
###

express = require 'express'
db = require('couchdb').createClient(5984, 'localhost').db('images')
temp = require 'temp'
fs = require 'fs'
im = require 'imagemagick'

app = express.createServer()

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
            db.saveDoc metadata, (err, doc) ->
                resizePath = temp.path('')
                im.resize {srcPath : path, dstPath: resizePath, width: metadata.width, height: metadata.height, quality: 0.96}, (err, stdout, stderr) ->
                    db.saveAttachment resizePath, doc.id, {name : 'clean.jpg', contentType: 'image/jpeg', 'rev' : doc.rev}, ->
                        fs.unlink(path)
                        fs.unlink(resizePath)
                res.send JSON.stringify({ok: true, id: doc.id}) + "\n", 201

app.listen 8000
