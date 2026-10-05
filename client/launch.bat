@echo off
rem Launches the exported Psykinetic client against the server.
rem tests/export_client.ps1 fills in the address and token when it bundles
rem this next to psykinetic.exe; the values here are placeholders.
set ADDRESS=SERVER_ADDRESS
set TOKEN=CHANGE_ME
start "" "%~dp0psykinetic.exe" --client --address=%ADDRESS% --token=%TOKEN%
