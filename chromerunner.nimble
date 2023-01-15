# Package

version       = "0.1.0"
author        = "jjv360"
description   = "Run a JavaScript app via Chrome instead of Node"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["chromerunner"]


# Dependencies

requires "nim >= 1.6.10"
requires "classes >= 0.2.13"