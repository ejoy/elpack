local loader = require "elploader"
loader.load("foobarx", {"foobar/.elp/foobar.0.elp" , "foobar/.elp/foobar.0.1.elp"})

require "foobar.hello"
require "foobar.hello2"

require "foobarx.hello"
require "foobarx.hello2"
