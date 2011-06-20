
###
tests for target image sizing
###

assert = require('assert')
target = require('./target')

module.exports =
  'chooses width for wide images': ->
    dim = target({width: 600, height: 240}, {max_width: 300, max_height: 180})
    assert.equal(dim.width, 300);
    assert.equal(dim.height, 0);
  'chooses height for tall images': ->
    dim = target({width: 240, height: 600}, {max_width: 300, max_height: 180})
    assert.equal(dim.width, 0);
    assert.equal(dim.height, 180);
  'chooses width for tall images that would still be too wide': ->
    dim = target({width: 400, height: 600}, {max_width: 240, max_height: 384})
    assert.equal(dim.width, 240);
    assert.equal(dim.height, 0);
  'chooses height for wide images what would still be too tall': ->
    dim = target({width: 800, height: 720}, {max_width: 520, max_height: 432})
    assert.equal(dim.width, 0);
    assert.equal(dim.height, 432);
  'chooses width when the aspect ratio is the same': ->
    dim = target({width: 800, height: 600}, {max_width: 640, max_height: 480})
    assert.equal(dim.width, 640);
    assert.equal(dim.height, 0);
  'fixed width': ->
    dim = target({width: 800, height: 600}, {width: 588})
    assert.equal(dim.width, 588);
    assert.equal(dim.height, 0);
  'fixed height': ->
    dim = target({width: 800, height: 600}, {height: 372})
    assert.equal(dim.width, 0);
    assert.equal(dim.height, 372);
