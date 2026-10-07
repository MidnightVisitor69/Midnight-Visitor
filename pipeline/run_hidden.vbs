' Starts the runner with no console window, so overnight runs never pop up over games or streams.
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""E:\AI\Waifu Card Game\pipeline\run.ps1""", 0, False
