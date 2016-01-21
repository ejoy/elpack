local loader = require "elploader"
loader.load("foobar", {"foobar/.elp/foobar.0.elp" , "foobar/.elp/foobar.0.1.elp"})
require "foobar.hello"
require "foobar.hello2"
