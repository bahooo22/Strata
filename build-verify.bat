@echo off
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
