imagenie
========

imagenie is a simple web app for RESTful image hosting intended for learning and
study

Try this
--------

Warning: before starting, go get some kitten JPEGs

    # create images database in CouchDB
    curl -X PUT http://localhost:5984/images
    # start app
    coffee images.coffee
    # create an album named 'kittens' with thumbnails 120 pixels tall/wide
    curl -X PUT -H 'Content-Type: application/json' --data '{"thumb" : {"max_height" : 120, "max_width" : 120}}' http://localhost:8000/kittens
    # post a picture to the album
    curl -i -H 'Content-type: image/jpeg' --data-binary @/path/to/kitten/picture.jpg http://localhost:8000/kittens
    # -> {"ok":true,"id":"2280dd0d2ecd3ebf091bea9d7d005d49"}
    # get your picture back (metadata will be striped out)
    curl -o /tmp/kitten.jpg http://localhost:8000/kittens/2280dd0d2ecd3ebf091bea9d7d005d49.jpg
    # get the thumbnail
    curl -o /tmp/kitten-thumb.jpg http://localhost:8000/kittens/thumb/2280dd0d2ecd3ebf091bea9d7d005d49.jpg
    # get some image metadata in JSON format
    curl http://localhost:8000/kittens/2280dd0d2ecd3ebf091bea9d7d005d49.json

'thumb' is an arbitrary size identifier, you can specify as many as you want
like profile, reduced, email, etc.

Tech
----
Technologies used in this project (in no particular order)

* [Node.js](http://nodejs.org)
* [Express.js](http://expressjs.com/)
* [CoffeeScript](http://coffeescript.org/)
* [Imagemagick](http://www.imagemagick.org/) and [node-imagemagick](https://github.com/rsms/node-imagemagick) for node integration
* [CouchDB](http://couchdb.apache.org/) and [node-couchdb](https://github.com/felixge/node-couchdb) for node integration

License
-------
Licensed under the MIT license (see LICENSE for details)
