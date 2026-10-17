# ohos-env.ps1 - Session-level env switch for OHOS Flutter (CPF-Flutter).
# Usage:  . D:\code\BeeCount-ohos\beecount-ohos\tool\ohos\ohos-env.ps1
# Check:  flutter --version should report 3.27.5-ohos-1.0.8
# Note:   only affects the CURRENT PowerShell session; the system-wide
#         flutter (3.38.9 standard) stays untouched.

# --- CPF Flutter (OHOS adaptation) ---
$env:Path = "D:\flutter-ohos\flutter_flutter\bin;$env:Path"
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
# silence "unknown channel / unknown source" warning from flutter doctor
$env:FLUTTER_GIT_URL = "https://gitcode.com/CPF-Flutter/flutter_flutter.git"
# PUB_CACHE must be a REAL directory on the same drive as the project (D:).
# Two hard constraints from the CPF/hvigor toolchain:
# 1. hvigor generates RELATIVE srcPath for plugin includes; path.relative
#    cannot cross drives (project on D:, default pub cache on C:).
# 2. hvigor validates fs.realpathSync.native(path) === path, so junctions or
#    symlinks to the C: cache are rejected ("Path not found 00303149").
# First run re-downloads hosted/git packages into this cache.
$env:PUB_CACHE = "D:\pub-cache"

# --- DevEco Studio / HarmonyOS SDK ---
$env:DEVECO_SDK_HOME = "C:\Program Files\Huawei\DevEco Studio\sdk"
$env:Path += ";C:\Program Files\Huawei\DevEco Studio\tools\ohpm\bin"
$env:Path += ";C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin"
$env:Path += ";C:\Program Files\Huawei\DevEco Studio\tools\node"

Write-Host "OHOS Flutter env loaded (CPF 3.27.5-ohos-1.0.8)" -ForegroundColor Green
flutter --version
