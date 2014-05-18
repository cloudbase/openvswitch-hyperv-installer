// Copyright (c) 2012 Cloudbase Solutions Srl. All rights reserved.

// Begin common utils (as there's no practival way to include a separate script)

// Awful workaround to include common js features
var commonIncludeFileName = "26DB88BF-D32F-4195-9159-8EA58CCFE3BE.js";
function loadCommonIncludeFile(fileName) {
    var shell = new ActiveXObject("WScript.Shell");
    var windir = shell.ExpandEnvironmentStrings("%WINDIR%");
    var path = windir + "\\Temp\\" + fileName;
    var fso = new ActiveXObject("Scripting.FileSystemObject");
    return fso.OpenTextFile(path, 1).ReadAll();
}
eval(loadCommonIncludeFile(commonIncludeFileName));
// End workaround

function runCommandAction() {
    var exceptionMsg = null;

    try {
        var data = Session.Property("CustomActionData").split('|');
        var i = 0;
        var cmd = data[i++];
        var expectedRetValue = data.length > i ? data[i++] : 0;
        var exceptionMsg = data.length > i ? data[i++] : null;
        var workingDir = data.length > i ? data[i++] : null;

        runCommand(cmd, expectedRetValue, null, 0, true, workingDir);
        return MsiActionStatus.Ok;
    }
    catch (ex) {
        if (exceptionMsg) {
            logMessageEx(exceptionMsg, MsgKind.Error + Icons.Critical + Buttons.OkOnly);
            // log also the original exception
            logMessage(ex.message);
        }
        else
            logException(ex);

        return MsiActionStatus.Abort;
    }
}