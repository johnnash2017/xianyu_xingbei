@echo off
rem 多开测试一键入口：把全部参数转发给同目录的 启动多开.ps1
rem 例：启动多开.bat              (默认 4 开)
rem     启动多开.bat -Count 6 -Auto
rem     启动多开.bat -EnginePath "D:\Godot\godot.exe"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0启动多开.ps1" %*