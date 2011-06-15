
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
    imagenie.saveImage req.params.album, req, (id) -> res.send JSON.stringify({ok: true, id: id}) + "\n", 201

app.get '/:album', (req, res) -> imagenie.getAlbum req.params.album, res
app.get '/:album/:id.jpg', (req, res) ->
    imagenie.retrieve(req.method, req.params.album, 'original', req.params.id, res)
app.get '/:album/:id.json', (req, res) ->
    imagenie.info(req.method, req.params.album, req.params.id, res)
app.get '/:album/:id', (req, res) ->
    imagenie.info(req.method, req.params.album, req.params.id, res)
app.get '/:album/:size/:id.jpg', (req, res) ->
    imagenie.retrieve(req.method, req.params.album, req.params.size, req.params.id, res)

app.listen 8000
