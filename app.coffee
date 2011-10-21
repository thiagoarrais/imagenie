
###
imagenie: an image hosting service
###

express = require 'express'

imagenie = require './imagenie'

app = express.createServer()
app.use(express.bodyParser())

error_codes =
    undefined: 201
    'conflict': 409
    'unknown': 500

app.put '/:album', (req, res) ->
    imagenie.saveAlbum req.params.album, req.query.hash, req.body, (result) ->
        res.send(JSON.stringify(result) + "\n", error_codes[result.error])

app.post '/:album', (req, res) ->
    imagenie.saveImage req.params.album, req, (status, result) ->
        body = JSON.stringify(result) + "\n"
        res.writeHead status, {
            'Content-Length': body.length,
            'Content-Type': 'application/json'}
        res.end body

app.get '/:album', (req, res) -> imagenie.getAlbum req.params.album, res
app.get '/:album/:id', (req, res) ->
    if req.header('Accept', '*/*').indexOf('application/json') >= 0
        imagenie.info(req.method, req.params.album, req.params.id, res)
    else
        imagenie.retrieve(req.method, req.params.album, 'original', req.params.id, res)

app.get '/:album/:size/:id', (req, res) ->
    imagenie.retrieve(req.method, req.params.album, req.params.size, req.params.id, res)

app.listen 8000
