
###
imagenie: an image hosting service
###

target = (orig, max) ->
    if orig.width / orig.height * max.max_height >= max.max_width
        width : max.max_width
        height : 0
    else
        height : max.max_height
        width : 0

module.exports = target
