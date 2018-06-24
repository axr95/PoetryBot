

for /f "delims=|" %%f in ('dir /b saved') do mspaint /pt "saved\%%f"
pause