import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/community_repository.dart';
import 'community_chat_screen.dart';

class CreateCommunityScreen extends StatefulWidget {
  final CommunityRepository repository;
  final bool initialIsChannel;

  const CreateCommunityScreen({
    super.key,
    required this.repository,
    this.initialIsChannel = false,
  });

  @override
  State<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends State<CreateCommunityScreen> {
  int _currentStep = 0; // 0: Type, 1: Info, 2: Visibility & Settings, 3: Invite

  // Step 1
  late bool _isChannel;

  // Step 2
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  File? _selectedImage;

  // Step 3
  String _visibility = 'public'; // 'public' | 'private'
  final _usernameController = TextEditingController();
  Timer? _usernameDebounce;
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameError;
  bool _approveNewMembers = false;
  String _whoCanSend = 'all';

  // Step 4
  final List<String> _selectedMembers = [];
  final TextEditingController _memberSearchController = TextEditingController();

  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _isChannel = widget.initialIsChannel;
    if (_isChannel) {
      _whoCanSend = 'admins_only';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _usernameController.dispose();
    _memberSearchController.dispose();
    _usernameDebounce?.cancel();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 600,
      maxHeight: 600,
    );
    if (picked != null) {
      setState(() => _selectedImage = File(picked.path));
    }
  }

  void _onUsernameChanged(String val) {
    _usernameDebounce?.cancel();
    final clean = val.trim().replaceAll('@', '').toLowerCase();

    if (clean.isEmpty) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = null;
        _usernameError = null;
      });
      return;
    }

    if (clean.length < 3) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameError = 'Must be at least 3 characters';
      });
      return;
    }

    final validChars = RegExp(r'^[a-z0-9_]+$');
    if (!validChars.hasMatch(clean)) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = false;
        _usernameError = 'Only letters, numbers and underscores';
      });
      return;
    }

    setState(() {
      _isCheckingUsername = true;
      _usernameError = null;
    });

    _usernameDebounce = Timer(const Duration(milliseconds: 400), () async {
      final available = await widget.repository.checkUsernameAvailable(clean);
      if (mounted) {
        setState(() {
          _isCheckingUsername = false;
          _isUsernameAvailable = available;
          _usernameError = available ? null : 'Username is already taken';
        });
      }
    });
  }

  Future<void> _submitCreate() async {
    final name = _nameController.text.trim();
    final desc = _descController.text.trim();
    final username = _usernameController.text.trim().replaceAll('@', '').toLowerCase();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a community name.')),
      );
      return;
    }

    if (_visibility == 'public' && username.isNotEmpty && _isUsernameAvailable == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose an available username.')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final settings = {
        'who_can_send': _isChannel ? 'admins_only' : _whoCanSend,
        'media_permissions': {
          'text': true,
          'photo': true,
          'video': true,
          'file': true,
          'call': true,
        },
        'approve_new_members': _approveNewMembers,
        'delete_mode': 'everyone',
      };

      final newCommId = await widget.repository.createCommunity(
        name: name,
        description: desc,
        isChannel: _isChannel,
        visibility: _visibility,
        username: (_visibility == 'public' && username.isNotEmpty) ? username : null,
        settings: settings,
        imageFile: _selectedImage,
        initialMembers: _selectedMembers.isNotEmpty ? _selectedMembers : null,
      );

      if (mounted) {
        Navigator.pop(context, true);
        final createdComm = await widget.repository.getCommunityById(newCommId);
        if (createdComm != null && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CommunityChatScreen(
                community: createdComm,
                repository: widget.repository,
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () {
            if (_currentStep > 0) {
              setState(() => _currentStep--);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          _getStepTitle(),
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_currentStep + 1) / 4,
            backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6)),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _buildCurrentStep(cardBg, textColor, isDark),
      ),
      bottomNavigationBar: _buildBottomBar(cardBg, isDark),
    );
  }

  String _getStepTitle() {
    switch (_currentStep) {
      case 0:
        return 'Step 1: Choose Type';
      case 1:
        return 'Step 2: Basic Info';
      case 2:
        return 'Step 3: Visibility & Settings';
      case 3:
        return 'Step 4: Add Members';
      default:
        return 'Create Community';
    }
  }

  Widget _buildCurrentStep(Color cardBg, Color textColor, bool isDark) {
    switch (_currentStep) {
      case 0:
        return _buildStep1Type(cardBg, textColor, isDark);
      case 1:
        return _buildStep2Info(cardBg, textColor, isDark);
      case 2:
        return _buildStep3Settings(cardBg, textColor, isDark);
      case 3:
        return _buildStep4Members(cardBg, textColor, isDark);
      default:
        return const SizedBox.shrink();
    }
  }

  // ── Step 1: Type Selection (Group vs Channel) ──
  Widget _buildStep1Type(Color cardBg, Color textColor, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What would you like to create?',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: textColor,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Choose between an interactive group or an announcement channel.',
          style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 24),

        // Group Card
        _buildTypeCard(
          isSelected: !_isChannel,
          title: 'Group',
          subtitle: 'Interactive community for 2-way messaging, media sharing, and discussions among members.',
          icon: Icons.group_rounded,
          iconColor: const Color(0xFF16A34A),
          bgColor: const Color(0xFFDCFCE7),
          onTap: () => setState(() => _isChannel = false),
          isDark: isDark,
        ),
        const SizedBox(height: 16),

        // Channel Card
        _buildTypeCard(
          isSelected: _isChannel,
          title: 'Channel',
          subtitle: 'Broadcast tool to send messages and announcements to an unlimited number of subscribers.',
          icon: Icons.campaign_rounded,
          iconColor: const Color(0xFF0284C7),
          bgColor: const Color(0xFFE0F2FE),
          onTap: () => setState(() => _isChannel = true),
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildTypeCard({
    required bool isSelected,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? const Color(0xFF3B82F6) : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      if (isSelected)
                        const Icon(Icons.check_circle_rounded, color: Color(0xFF3B82F6), size: 22),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 2: Basic Info (Name, Description, Logo) ──
  Widget _buildStep2Info(Color cardBg, Color textColor, bool isDark) {
    final typeStr = _isChannel ? 'Channel' : 'Group';

    return Column(
      children: [
        // Avatar picker
        GestureDetector(
          onTap: _pickImage,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: _isChannel ? const Color(0xFFE0F2FE) : const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(24),
                  image: _selectedImage != null
                      ? DecorationImage(image: FileImage(_selectedImage!), fit: BoxFit.cover)
                      : null,
                ),
                child: _selectedImage == null
                    ? Icon(
                        _isChannel ? Icons.campaign_rounded : Icons.group_rounded,
                        size: 44,
                        color: _isChannel ? const Color(0xFF0284C7) : const Color(0xFF16A34A),
                      )
                    : null,
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6),
                  shape: BoxShape.circle,
                  border: Border.all(color: cardBg, width: 2),
                ),
                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tap to upload logo',
          style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 24),

        // Name input
        TextField(
          controller: _nameController,
          maxLength: 100,
          textCapitalization: TextCapitalization.words,
          style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: '$typeStr Name *',
            hintText: 'e.g. Vadodara Tech Community',
            filled: true,
            fillColor: cardBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 12),

        // Description input
        TextField(
          controller: _descController,
          maxLines: 3,
          maxLength: 250,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(color: textColor),
          decoration: InputDecoration(
            labelText: 'Description (Optional)',
            hintText: 'What is this $typeStr about?',
            filled: true,
            fillColor: cardBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }

  // ── Step 3: Visibility & Settings ──
  Widget _buildStep3Settings(Color cardBg, Color textColor, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Community Visibility',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor),
        ),
        const SizedBox(height: 12),

        // Public Radio
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _visibility == 'public' ? const Color(0xFF3B82F6) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: RadioListTile<String>(
            title: const Text('Public', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Anyone can find and join via search or public link'),
            value: 'public',
            groupValue: _visibility,
            onChanged: (val) => setState(() => _visibility = val!),
          ),
        ),
        const SizedBox(height: 8),

        // Private Radio
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _visibility == 'private' ? const Color(0xFF3B82F6) : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: RadioListTile<String>(
            title: const Text('Private', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Can only be joined via private invite link or approval'),
            value: 'private',
            groupValue: _visibility,
            onChanged: (val) => setState(() => _visibility = val!),
          ),
        ),

        // Public Username Field
        if (_visibility == 'public') ...[
          const SizedBox(height: 20),
          Text(
            'Public Username & Link',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _usernameController,
            onChanged: _onUsernameChanged,
            style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              prefixText: 'app://c/',
              prefixStyle: const TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold),
              hintText: 'username',
              filled: true,
              fillColor: cardBg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              suffixIcon: _isCheckingUsername
                  ? const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : (_isUsernameAvailable != null
                      ? Icon(
                          _isUsernameAvailable! ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          color: _isUsernameAvailable! ? const Color(0xFF16A34A) : Colors.red,
                        )
                      : null),
              errorText: _usernameError,
            ),
          ),
        ],

        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 12),

        // Approve New Members Toggle
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Approve new members', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('Require admin review before requests are accepted'),
          value: _approveNewMembers,
          onChanged: (val) => setState(() => _approveNewMembers = val),
        ),

        // Who can send messages (Groups only)
        if (!_isChannel) ...[
          const SizedBox(height: 12),
          Text(
            'Who can send messages',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                RadioListTile<String>(
                  title: const Text('All members'),
                  value: 'all',
                  groupValue: _whoCanSend,
                  onChanged: (val) => setState(() => _whoCanSend = val!),
                ),
                RadioListTile<String>(
                  title: const Text('Admins only'),
                  value: 'admins_only',
                  groupValue: _whoCanSend,
                  onChanged: (val) => setState(() => _whoCanSend = val!),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Step 4: Add Members / Invite ──
  Widget _buildStep4Members(Color cardBg, Color textColor, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add Initial Members',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
        ),
        const SizedBox(height: 6),
        const Text(
          'You can add members now or share the link later.',
          style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _memberSearchController,
          decoration: InputDecoration(
            hintText: 'Enter user handle (e.g. rahul_v)',
            prefixIcon: const Icon(Icons.person_add_alt_1_rounded),
            filled: true,
            fillColor: cardBg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add_circle, color: Color(0xFF3B82F6)),
              onPressed: () {
                final h = _memberSearchController.text.trim().replaceAll('@', '');
                if (h.isNotEmpty && !_selectedMembers.contains(h)) {
                  setState(() {
                    _selectedMembers.add(h);
                    _memberSearchController.clear();
                  });
                }
              },
            ),
          ),
          onSubmitted: (val) {
            final h = val.trim().replaceAll('@', '');
            if (h.isNotEmpty && !_selectedMembers.contains(h)) {
              setState(() {
                _selectedMembers.add(h);
                _memberSearchController.clear();
              });
            }
          },
        ),
        const SizedBox(height: 16),

        if (_selectedMembers.isNotEmpty) ...[
          Text(
            'Added Members (${_selectedMembers.length})',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedMembers.map((m) {
              return Chip(
                avatar: CircleAvatar(
                  backgroundColor: const Color(0xFF3B82F6),
                  child: Text(m[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10)),
                ),
                label: Text('@$m'),
                onDeleted: () {
                  setState(() => _selectedMembers.remove(m));
                },
              );
            }).toList(),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(Icons.people_outline_rounded, size: 48, color: const Color(0xFF94A3B8).withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                const Text('No members added yet. You can invite people anytime!'),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Bottom Action Bar ──
  Widget _buildBottomBar(Color cardBg, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _isCreating
                ? null
                : () {
                    if (_currentStep < 3) {
                      if (_currentStep == 1 && _nameController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a name.')),
                        );
                        return;
                      }
                      setState(() => _currentStep++);
                    } else {
                      _submitCreate();
                    }
                  },
            child: _isCreating
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(
                    _currentStep == 3 ? 'Create ${_isChannel ? "Channel" : "Group"}' : 'Continue',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ),
    );
  }
}