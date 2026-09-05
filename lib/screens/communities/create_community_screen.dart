import 'package:flutter/material.dart';
import '../../services/community_repository.dart';

class CreateCommunityScreen extends StatefulWidget {
  final CommunityRepository repository;
  final bool isChannel;

  const CreateCommunityScreen({
    super.key,
    required this.repository,
    required this.isChannel,
  });

  @override
  State<CreateCommunityScreen> createState() => _CreateCommunityScreenState();
}

class _CreateCommunityScreenState extends State<CreateCommunityScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  bool _isLoading = false;

  Future<void> _create() async {
    if (_nameController.text.trim().isEmpty) return;
    
    setState(() => _isLoading = true);
    
    try {
      await widget.repository.createCommunity(
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        isChannel: widget.isChannel,
      );
      if (mounted) {
        Navigator.pop(context); // Go back
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.isChannel ? 'Channel' : 'Group';
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text('Create New $type', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.black87),
              decoration: InputDecoration(
                labelText: '$type Name',
                labelStyle: const TextStyle(color: Colors.black54),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              style: const TextStyle(color: Colors.black87),
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Description (What is this $type about?)',
                labelStyle: const TextStyle(color: Colors.black54),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _create,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text('Create $type', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
