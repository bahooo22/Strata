@echo off
rem LEGACY: this file targets the old E: layout (engine sources and .venv next to START-HERE.bat);
rem it fails with "path not found" on the 0.2.16 layout where sources live in C:\Projects\Strata-3060Ti\engine.
rem The live path is UPDATE.bat / START-HERE.bat --update (compiles terminal/engine from this tree, checked 23.11).
rem Kept for the old workstation only; do not run from this clone.
rem Пересборка engine с ggml из соседнего git-клона llama.cpp (STRATA_GGML_DIR).
setlocal
set "ENGINE=E:\eXample\Documents\Source\Github\Strata-3060Ti\engine"
set "LLAMA=E:\eXample\Documents\Source\Github\Strata-3060Ti\llama.cpp"
set "VS_DIR=F:\Program Files\Microsoft Visual Studio\18\Professional"
set "CUDA_DIR=F:\CUDA\cuda-13.3"

call "%VS_DIR%\VC\Auxiliary\Build\vcvars64.bat"
if errorlevel 1 exit /b 1
set "PATH=%CUDA_DIR%\bin;%ENGINE%\.venv\Scripts;%PATH%"
set "CMAKE=%ENGINE%\.venv\Lib\site-packages\cmake\data\bin\cmake.exe"

"%CMAKE%" -S "%ENGINE%" -B "%ENGINE%\build" -G Ninja -DCMAKE_BUILD_TYPE=Release ^
  -DSTRATA_ENABLE_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86 ^
  -DCMAKE_CUDA_COMPILER=%CUDA_DIR%\bin\nvcc.exe ^
  -DSTRATA_BUILD_TESTS=OFF -DSTRATA_GGML_DIR="%LLAMA%"
if errorlevel 1 exit /b 2
"%CMAKE%" --build "%ENGINE%\build" --target strata strata-q36 -j 4
exit /b %errorlevel%
