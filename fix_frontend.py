import re

files = [
    'lib/services/post_repository.dart',
    'lib/services/telegram_storage_service.dart'
]

for file in files:
    with open(file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Replace header in post_repository.dart
    content = content.replace("'x-session-token': sessionToken ?? '',", "'authorization': 'Bearer ${sessionToken ?? ''}',")
    
    # Replace header in telegram_storage_service.dart
    # e.g., ..headers['x-session-token'] = sessionToken
    content = content.replace("..headers['x-session-token'] = sessionToken", "..headers['authorization'] = 'Bearer $sessionToken'")
    
    with open(file, 'w', encoding='utf-8') as f:
        f.write(content)
