import 'package:flutter_test/flutter_test.dart';
import 'package:localv1/core/constants/areas_and_categories.dart';
import 'package:localv1/models/post_model.dart';

void main() {
  group('Vadodara Local Model Unit Tests', () {
    test('Post model instantiation test', () {
      final post = Post(
        id: 'test-123',
        authorHandle: 'Anon#A1B2C3',
        content: 'Verification test post content for Vadodara Local',
        
        category: PostCategory.traffic,
        createdAt: DateTime.now(),
        upvotes: 5,
        downvotes: 0,
        commentCount: 0,
        userVote: 0,
        isEmergency: false,
        reporters: const [],
      );

      expect(post.id, 'test-123');
      expect(post.authorHandle, 'Anon#A1B2C3');
      expect(post.score, 5);
      expect(post.category.label, 'Traffic');
      expect(post.area.displayName, 'Alkapuri');
    });
  });
}
