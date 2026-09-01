import re

with open('lib/screens/auth/device_register_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

replacement = '''
        final requestHashStr = 'POST/api/v1/devices/register$_deviceId';
        final requestHashBytes = utf8.encode(requestHashStr);
        final requestHash = sha256.convert(requestHashBytes).toString();
        final attestationToken = await DeviceInfoService.getPlayIntegrityToken(requestHash) ?? "simulated_attestation_com.example.localv1_$_deviceId";
'''

content = re.sub(
    r'final attestationToken = "simulated_attestation_com\.example\.localv1_\$_deviceId";',
    replacement.strip(),
    content
)

if 'import \'dart:convert\';' not in content:
    content = "import 'dart:convert';\nimport 'package:crypto/crypto.dart';\n" + content

with open('lib/screens/auth/device_register_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)

with open('lib/services/post_repository.dart', 'r', encoding='utf-8') as f:
    content2 = f.read()

replacement2 = '''
        final requestId = const Uuid().v4();
        final requestHashStr = 'POST/api/v1/posts/$postId/vote$direction$requestId';
        final requestHashBytes = utf8.encode(requestHashStr);
        final requestHash = sha256.convert(requestHashBytes).toString();
        final attestationToken = await DeviceInfoService.getPlayIntegrityToken(requestHash) ?? "simulated_attestation_com.example.localv1_$requestHash";
'''

content2 = re.sub(
    r'final attestationToken = "simulated_attestation_com\.example\.localv1_\$deviceId";',
    replacement2.strip(),
    content2
)

content2 = content2.replace("'attestationToken': attestationToken", "'attestationToken': attestationToken, 'requestId': requestId")

if 'import \'package:crypto/crypto.dart\';' not in content2:
    content2 = "import 'package:crypto/crypto.dart';\n" + content2

with open('lib/services/post_repository.dart', 'w', encoding='utf-8') as f:
    f.write(content2)
