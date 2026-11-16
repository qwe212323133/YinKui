@echo off
setlocal
rem ProfitLook Android one-click debug build for this workstation.
rem The machine's global JAVA_HOME points at a stale JRE 1.8 path, so pin JDK 17 here.
set "JAVA_HOME=E:\jdk-17.0.2"
set "ANDROID_HOME=C:\Users\Administrator\AppData\Local\Android\Sdk"
set "ANDROID_SDK_ROOT=%ANDROID_HOME%"
cd /d "%~dp0"
call "%~dp0gradlew.bat" --no-daemon assembleDebug %*
if errorlevel 1 (
  echo BUILD FAILED
  exit /b 1
)
set "APK=%~dp0app\build\outputs\apk\debug\app-debug.apk"
if exist "%APK%" (
  copy /Y "%APK%" "%USERPROFILE%\Desktop\ProfitLook-Android-debug.apk" >nul
  echo APK copied to %USERPROFILE%\Desktop\ProfitLook-Android-debug.apk
) else (
  echo APK not found: %APK%
  exit /b 1
)
endlocal
