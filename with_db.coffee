
###
Simple interface for nanocouch that automagically creates a missing database
###

couch = require('nano')('http://localhost:5984')

module.exports = withDB = (->
    db = null
    (action) ->
        if !db
            couch.db.get('images', (err) ->
                useImages = ->
                    db = couch.use('images')
                    action db
                if err
                    couch.db.create('images', useImages)
                else
                    useImages()
            )
        else
            action db
    )()
