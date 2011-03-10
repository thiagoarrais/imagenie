
###
imagenie: an image hosting service
###

express = require 'express'
db = require('couchdb').createClient(5984, 'localhost').db('images')
fs = require 'fs'
child = require 'child_process'
http = require 'http'
async = require 'async'

app = express.createServer()
app.use(express.bodyDecoder())

nonSizes = ['_id', '_rev']
reservedSizes = nonSizes + ['original']

client = null
resize = (imgSource, origSize, name, size, id) ->
    if origSize.width > origSize.height
        dstHeight = dstWidth = size.max_width
    else
        dstWidth = dstHeight = size.max_height
    imgResized = new Buffer(imgSource.length)
    length = 0
    resize = child.spawn 'convert', ['jpeg:-',
                                     '-resize', String(dstWidth)+'x'+String(dstHeight),
                                     '-quality', '96',
                                     'jpeg:-']
    resize.stdout.setEncoding 'binary'
    resize.stdout.on 'data', (chunk) ->
        imgResized.write(chunk, length, 'binary')
        length += chunk.length
    resize.on 'exit', ->
        retry = (id, name, imgData) ->
            db.getDoc id, (err, doc) ->
                client ||= http.createClient(5984)
                req = client.request 'PUT', '/images/'+id+'/'+name+'?rev='+doc['_rev'], {'Content-Type' : 'image/jpeg', 'Content-Length' : imgData.length}
                req.on 'response', (response) ->
                    retry(id, name, imgData) if response.statusCode == 409
                req.end imgData, null
        retry id, name, imgResized.slice(0, length)

    resize.stdin.end imgSource

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
    imgData = new Buffer parseInt(req.headers['content-length'])
    pos = 0
    imgInfo = ''
    identify = child.spawn('identify', ['-'])
    identify.stdout.on 'data', (chunk) -> imgInfo += chunk
    identify.on 'exit', ->
        v = imgInfo.split ' '
        x = v[2].split 'x'
        metadata =
            format: v[1]
            width: parseInt x[0]
            height: parseInt x[1]
            depth: parseInt v[4]
            album: req.params.album
        db.saveDoc metadata, (err, doc) ->
            imgClean = new Buffer(imgData.length * 2)
            pos = 0
            clean = child.spawn 'convert', ['jpeg:-',
                                            '-resize', String(metadata.width)+'x'+String(metadata.height),
                                            '-quality', '96',
                                            'jpeg:-']
            clean.stdout.setEncoding 'binary'
            clean.stdout.on 'data', (chunk) ->
                imgClean.write(chunk, pos, 'binary')
                pos += chunk.length
            clean.on 'exit', ->
                request = http.createClient(5984).request('PUT', '/images/' + doc.id + '/original?rev=' + doc.rev, {'Content-Type' : 'image/jpg', 'Content-Length': pos})
                request.on 'response', ->
                    db.getDoc req.params.album, (err, album) ->
                        (resize(imgClean.slice(0, pos), metadata, k, v, doc.id) unless nonSizes.indexOf(k) != -1) for own k, v of album
                request.end(imgClean.slice(0, pos), null)
            clean.stdin.end imgData
            res.send JSON.stringify({ok: true, id: doc.id}) + "\n", 201

    req.setEncoding 'binary'
    req.on 'data', (chunk) ->
        imgData.write(chunk, pos, 'binary')
        identify.stdin.write(chunk, 'binary')
        pos += chunk.length
    req.on 'end', ->
        identify.stdin.end()

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
