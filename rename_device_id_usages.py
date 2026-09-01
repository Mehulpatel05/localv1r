import re

with open('lib/screens/auth/device_register_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()
content = content.replace('getPersistentInstallationId', 'getInstallationId')
with open('lib/screens/auth/device_register_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)

with open('android/app/src/main/kotlin/com/example/localv1/MainActivity.kt', 'r', encoding='utf-8') as f:
    content = f.read()
content = content.replace('getPermanentInstallationId', 'getInstallationId')
with open('android/app/src/main/kotlin/com/example/localv1/MainActivity.kt', 'w', encoding='utf-8') as f:
    f.write(content)
