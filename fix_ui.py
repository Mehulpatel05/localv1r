import re

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Food screen changes
    if 'food_screen.dart' in filepath:
        content = content.replace('color: Colors.black87, // Card Background', 'color: Colors.white,')
        content = content.replace('color: Colors.black87,\n        borderRadius: BorderRadius.circular(16),', 'color: Colors.white,\n        borderRadius: BorderRadius.circular(16),')
        content = content.replace('color: const Color(0xFF1E3A3A),', 'color: const Color(0xFFE2E8F0),')
        content = content.replace('color: Colors.black87, size: 22', 'color: Colors.white, size: 22')
        content = content.replace('color: Colors.black87,\n                                  fontSize: 12,', 'color: Colors.white,\n                                  fontSize: 12,')
        content = content.replace('color: Colors.black87, size: 14', 'color: Colors.white, size: 14')
        content = content.replace('Divider(color: Color(0xFF243049)', 'Divider(color: Colors.grey.shade200')

    # Events screen changes
    elif 'events_screen.dart' in filepath:
        content = content.replace('color: const Color(0xFF19122A),', 'color: Colors.white,')
        content = content.replace('border: Border.all(color: const Color(0xFF2E224D)),', 'border: Border.all(color: Colors.grey.shade200),')
        content = content.replace('color: const Color(0xFF8B5CF6).withOpacity(0.1),', 'color: Colors.black.withOpacity(0.04),')
        content = content.replace('color: const Color(0xFF332057),', 'color: const Color(0xFFE2E8F0),')
        content = content.replace('color: Colors.black87,\n                          borderRadius: BorderRadius.circular(12),', 'color: Colors.white,\n                          borderRadius: BorderRadius.circular(12),')
        content = content.replace('color: Colors.black.withOpacity(0.3),', 'color: Colors.black.withOpacity(0.08),')
        content = content.replace('color: Colors.black87,\n                                fontSize: 20,', 'color: Colors.black87,\n                                fontSize: 20,') # Keep black for date text
        
        # Price tag overlay
        content = content.replace('color: Colors.black.withOpacity(0.7),', 'color: Colors.white,')
        content = content.replace('border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.5)),', 'border: Border.all(color: Colors.grey.shade300),')
        # We need to make sure the price text is black87
        content = content.replace('style: const TextStyle(color: Colors.black87,\n                            fontSize: 13,', 'style: const TextStyle(color: Colors.black87,\n                            fontSize: 13,')

        # Location text in events
        content = content.replace('color: const Color(0xFFA78BFA),', 'color: Colors.black54,')
        content = content.replace('color: const Color(0xFFC4B5FD),', 'color: Colors.black54,')
        
        # User review content text
        content = content.replace('color: const Color(0xFFD8B4FE),', 'color: Colors.black87,')
        
        # Icons
        content = content.replace('color: const Color(0xFF8B5CF6)', 'color: Colors.black54')
        
        # Divider
        content = content.replace('Divider(color: Color(0xFF2E224D)', 'Divider(color: Colors.grey.shade200')

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

process_file('lib/screens/food/food_screen.dart')
process_file('lib/screens/events/events_screen.dart')
print("Fixed files!")
