on run
    set launcherPath to (POSIX path of (path to me)) & "Contents/Resources/codex-company.command"
    try
        do shell script "/bin/test -x " & quoted form of launcherPath
        tell application "Terminal.app"
            do script (quoted form of launcherPath)
            activate
        end tell
    on error errorMessage
        display dialog "公司 Codex 启动失败：" & return & errorMessage buttons {"确定"} default button "确定" with icon stop
    end try
end run

