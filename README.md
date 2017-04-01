imagenie
========

imagenie is a simple web app for RESTful image hosting.

this is a toy project for study only. do not use it in production.

Try this
--------

Warning: before starting, go get some kitten JPEGs and make sure the CouchDB
server is listening on localhost:5984

    # start app
    coffee images.coffee
    # create an album named 'kittens' with thumbnails 120 pixels tall/wide
    curl -X PUT -H 'Content-Type: application/json' --data '{"thumb" : {"max_height" : 120, "max_width" : 120}}' http://localhost:8000/kittens
    # post a picture to the album
    curl -i -H 'Content-Type: image/jpeg' --data-binary @/path/to/kitten/picture.jpg http://localhost:8000/kittens
    # -> {"ok":true,"id":"2280dd0d2ecd3ebf091bea9d7d005d49"}
    # get your picture back (metadata will be striped out)
    curl -o /tmp/kitten.jpg http://localhost:8000/kittens/2280dd0d2ecd3ebf091bea9d7d005d49
    # get the thumbnail
    curl -o /tmp/kitten-thumb.jpg http://localhost:8000/kittens/thumb/2280dd0d2ecd3ebf091bea9d7d005d49
    # get some image metadata in JSON format
    curl -H 'Accept: application/json' http://localhost:8000/kittens/2280dd0d2ecd3ebf091bea9d7d005d49

'thumb' is an arbitrary size identifier, you can specify as many as you want
like profile, reduced, email, etc.

Tech
----
Technologies used in this project (in no particular order)

* [Node.js](http://nodejs.org)
* [Express.js](http://expressjs.com/)
* [CoffeeScript](http://coffeescript.org/)
* [Imagemagick](http://www.imagemagick.org/) and [node-imagemagick](https://github.com/rsms/node-imagemagick) for node integration
* [CouchDB](http://couchdb.apache.org/) and [nanocouch](https://github.com/dscape/nano) for node integration

License
-------
Licensed under the MIT license (see LICENSE for details)
