imagenie
========

imagenie is a simple web app for RESTful image hosting intended for learning and
study

Try this
--------

Warning: before starting, go get some kitten JPEGs

    # start app
    coffee images.coffee
    # create an album named 'kittens' with thumbnails 120 pixels tall/wide
    curl -X PUT http://localhost:8000/kittens --data '{"thumb" : {"max_height" : 120, "max_width" : 120}}'
    # post a picture to the album
    curl -i -H 'Content-type: image/jpeg' --data-binary @/path/to/kitten/picture.jpg http://localhost:8000/kittens
    # -> {"ok":true,"id":"2280dd0d2ecd3ebf091bea9d7d005d49"}
    # get your picture back (metadata will be striped out)
    curl -o /tmp/kitten.jpg http://localhost:8000/kittens/2280dd0d2ecd3ebf091bea9d7d005d49/original.jpg
    # get the thumbnail
    curl -o /tmp/kitten-thumb.jpg http://localhost:8000/kittens/2280dd0d2ecd3ebf091bea9d7d005d49/thumb.jpg

'thumb' is an arbitrary size identifier, you can specify as many as you want
like profile, reduced, email, etc.

License
-------
Licensed under the MIT license (see LICENSE for details)
