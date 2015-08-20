package="mnigs"
version="0.1.0-1"
source = {
  url = "git://github.com/pdxmeshnet/mnigs.git",
  tag = "0.1.0"
}
description = {
   summary = "Mnigs is an automated Internet gateway publish, search and connect tool for mesh networks.",
   detailed = [[
      The goal of this package is to provide gateway owners the function to automatically advertise their gateway on the network and to provide users the automated Internet gateway search and connect function for their routers.
   ]],
   homepage = "http://github.com/pdxmeshnet/mnigs/",
   license = "MIT"
}
dependencies = {
   "lua >= 5.1",
   "luasocket",
   "cgilua",
   "lua-cjson",
   "inifile",
   "xavante",
   "jsonrpc4lua",
   "sha2",
   "bencode",
   "dkjson",
   "bit32"
}

build = {
   type = "builtin",
}
