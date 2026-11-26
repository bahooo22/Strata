@echo off
title Strata qwen36-IQ4_XS-KAT
cd /d "C:\Projects\Strata-3060Ti\engine\terminal"
"C:\Projects\Strata-3060Ti\engine\terminal\.venv\Scripts\python.exe" "C:\Projects\Strata-3060Ti\engine\terminal\serve\server.py" "--engine" "strata" "--config" "C:\Projects\Strata-3060Ti\engine\terminal\strata-qwen36-iq4_xs-kat.json" "--port" "8080" "--open"
if errorlevel 1 pause
