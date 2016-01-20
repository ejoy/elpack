local mainpath = arg[0]:match("(.*)[/\\].*$") or "."
local sep = string.match (package.config, "[^\n]+")
local ext = string.match (package.cpath, "%?%.([^;]+);?")

package.path = mainpath .. sep .. "?.lua"
package.cpath = mainpath .. sep .. "?." .. ext

local mod = (...)
local f = require ("elp." .. mod)
f(select(2, ...))

