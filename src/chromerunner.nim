#
# This library allows you to run your JavaScript app via Chrome instead of via Node.

import std/asyncdispatch
when not defined(js):
    import std/os
    import std/osproc
    import std/tempfiles
    import std/exitprocs
    import std/strutils

## Locations to search for the Chrome binary. Exposed so that library users can extend it.
var chromeBinaryLocations* = @[

    # Common paths on Windows
    "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe", 
    "C:/Program Files (x86)/Google/Application/chrome.exe", 
    "~/AppDataLocal/Google/Chrome/chrome.exe",

    # Common paths on *nix
    "/usr/bin/google-chrome", 
    "/usr/local/sbin/google-chrome", 
    "/usr/local/bin/google-chrome", 
    "/usr/sbin/google-chrome", 
    "/usr/bin/chrome", 
    "/sbin/google-chrome", 
    "/bin/google-chrome",

    # Common paths on MacOS
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "~/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",

]

## Find the location of the Chrome binary, or return a blank string if not found
proc findChromeBinaryPath*(): string =

    # Check environment
    when defined(js):

        # Not supported
        return ""

    else:

        # Go through each path and check if it exists
        for path in chromeBinaryLocations:
            let expandedPath = expandTilde(path)
            if fileExists(expandedPath):
                return path

        # Not found
        return ""


## Launch Chrome and start running the specified file
## - jsFile : Path to the JavaScript file to run
## - headless : If true, Chrome will be run without any visible UI. If false, the app window will be shown.
## - detached : If true, will not attach to the console or wait for the app to exit (ie when the app calls `window.close()`)
## - windowSize : The app window size, eg "1024,768"
proc runChromeWithScript*(jsFile: string, headless: bool = true, detached: bool = false, htmlTemplate: string = "", windowSize: string = "800,600") {.async.} =

    # Check environment
    when defined(js):

        # Not supported
        raiseAssert("Cannot be used from JavaScript.")

    else:

        # Check input
        if not fileExists(jsFile): raiseAssert("The JS file does not exist.")

        # Find Chrome EXE
        let chromeExe = findChromeBinaryPath()
        if chromeExe == "":
            raiseAssert("Unable to find the Chrome binary. Please ensure that Chrome is installed, and that it's path is added to 'chromeBinaryLocations' if necessary.")

        # Create a temporary directory for the web app and chrome data
        let tempPath = createTempDir(prefix = "chromerunner", suffix = "app")
        # createDir(tempPath / "chromedata")

        # Delete the temporary directory after program execution, unless we are in detached mode (since Chrome needs these files indefinitely in that case)
        if not detached: addExitProc(proc() =
            try:
                removeDir(tempPath)
            except:
                discard
        )

        # Generate the HTML template
        var htmlStr = htmlTemplate
        if htmlStr == "": htmlStr = """
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <title>App</title>
                <meta charset="utf-8"/>
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
            </head>
            <body>

                <!-- Style -->
                <style>
                    html, body {
                        padding: 0px;
                        margin: 0px;
                        cursor: default;
                        user-select: none;
                    }
                </style>

                <!-- Hook to catch the window closing -->
                <!-- TODO: Isn't there a way for the Chrome process to exit itself when the last window closes? -->
                <script>
                    window.addEventListener("unload", () => console.log("CHROMERUNNER:WINDOWCLOSE"))
                    var originalWindowClose = window.close
                    window.close = function() {
                        console.log("CHROMERUNNER:WINDOWCLOSE")
                        originalWindowClose()
                    }
                </script>

                <!-- App code -->
                <script src="main.js"></script>

            </body>
            </html>
        """

        # Save it to the temporary directory
        writeFile(tempPath / "index.html", htmlStr)

        # Copy the input script to the directory as well
        copyFile(jsFile, tempPath / "main.js")

        # Generate command line arguments
        # See: https://peter.sh/experiments/chromium-command-line-switches/
        # See: https://github.com/puppeteer/puppeteer/blob/756ed705b1ca260c7739d7738bd043260dbe0b88/src/node/Launcher.ts#L204
        var args = @[
            # "file://" & (tempPath / "index.html"),
            if headless: "file://" & (tempPath / "index.html") else: "--app=file://" & (tempPath / "index.html"),
            # "--app=https://google.com",
            "--allow-file-access",
            "--allow-file-access-from-files",
            "--window-size=" & windowSize,
            "--user-data-dir=" & (tempPath / "chromedata"),
            # "--chrome-frame",
            # "--single-process"
            "--enable-logging=stderr",
            # "--disable-zero-browsers-open-for-tests",
            # "--kiosk",
            # "--disable-renderer-backgrounding",
            # "--disable-background-networking",
            # "--disable-extensions",     # <-- Extensions may prevent the process from exiting when the window is closed
            # "--disable-component-extensions-with-background-pages",
            # "--disable-features=Translate",
            # "--disable-backgrounding-occluded-windows",
            "--disable-breakpad",
            "--no-first-run"
        ]

        # Add debugging port if not detached
        # if not detached:
        #     args.add("--remote-debugging-port=0")

        # Add headless flag if requested
        if headless:
            args.add("--headless")

        # Launch the process
        let process = startProcess(chromeExe, args = args, options = { poStdErrToStdOut })
        if detached:
            return

        # Monitor Chrome's output and log console.log() messages
        for line in process.lines:

            # Strip out console.log() entries and get the raw output
            let idx1 = line.find("] \"")
            if idx1 == -1: continue
            let idx2 = line.find("\", source: ", idx1-1)
            if idx2 == -1: continue
            let logLine = line.substr(idx1 + 3, idx2-1)

            # Check for the window close hook
            if logLine == "CHROMERUNNER:WINDOWCLOSE":
                break

            # Output the line
            echo logLine

        # Done, end the Chrome process in case it's still sticking around
        if process.running():
            process.terminate()
        



# When run as a CLI tool, parse the input
when isMainModule:
    import std/parseopt
    import std/tables

    # Print the help screen
    proc printHelp() = echo """

ChromeRunner - Run a JS script as if it was an application. Usage:

    chromerunner myfile.js

Optional command line flags:

    --detached      Does not wait for the app to exit via window.close()
    --headless      Prevents any UI from being shown

    """.strip()

    # Process CLI
    proc runCLI() =

        # Decode command line options
        var commandLineOptions: Table[string, string]
        var commandLineArgs: seq[string]
        var parser = initOptParser()
        while true:
            parser.next()
            case parser.kind:
                of cmdEnd: break
                of cmdShortOption, cmdLongOption:
                    commandLineOptions[parser.key] = if parser.val == "": "on" else: parser.val
                of cmdArgument:
                    commandLineArgs.add(parser.key)

        # Check input
        if commandLineArgs.len == 0:
            printHelp()
            return

        # Run it
        let scriptPath = commandLineArgs[0]
        waitFor runChromeWithScript(scriptPath, 
            headless = commandLineOptions.hasKey("headless"), 
            detached = commandLineOptions.hasKey("detached"), 
            windowSize = commandLineOptions.getOrDefault("window-size", "800,600")
        )


    # Run the CLI
    runCLI()

