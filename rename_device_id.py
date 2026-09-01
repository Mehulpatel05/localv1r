import re

with open('lib/services/device_info_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Rename getPersistentInstallationId to getInstallationId
content = content.replace('getPersistentInstallationId', 'getInstallationId')
content = content.replace('getPermanentInstallationId', 'getInstallationId')

with open('lib/services/device_info_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)
