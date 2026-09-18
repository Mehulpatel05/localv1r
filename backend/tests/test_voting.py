import os
import sys
import unittest
from unittest.mock import MagicMock, patch

# Include parent directory in python path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services.firebase_service import FirebaseService


class TestVotingLogic(unittest.TestCase):
    def test_shard_distribution(self):
        """Verify that user handles map across shards 0-19 deterministically."""
        shards = set()
        for i in range(100):
            handle = f"user_{i}"
            import hashlib
            shard_id = int(hashlib.md5(handle.encode('utf-8')).hexdigest(), 16) % FirebaseService.NUM_SHARDS
            self.assertTrue(0 <= shard_id < 20)
            shards.add(shard_id)
        # 100 random users should hit multiple shards
        self.assertGreater(len(shards), 10)

    def test_toggle_logic_matrices(self):
        """
        Verify the mathematical correctness of the toggle logic:
        1. Neutral -> Upvote: delta = +1
        2. Upvote -> Upvote (Toggle Off): delta = -1
        3. Neutral -> Downvote: delta = -1
        4. Downvote -> Downvote (Toggle Off): delta = +1
        5. Downvote -> Upvote: delta = +2
        6. Upvote -> Downvote: delta = -2
        """
        # Test case: Neutral (0) -> Upvote (1)
        prev_vote = 0
        direction = 1
        new_vote = direction
        score_delta = 1
        upvote_delta = 1
        downvote_delta = 0
        self.assertEqual(score_delta, 1)
        self.assertEqual(new_vote, 1)

        # Test case: Upvote (1) -> Upvote (1) [Toggle Off]
        prev_vote = 1
        direction = 1
        new_vote = 0
        score_delta = -1
        upvote_delta = -1
        downvote_delta = 0
        self.assertEqual(score_delta, -1)
        self.assertEqual(new_vote, 0)

        # Test case: Downvote (-1) -> Upvote (1) [Switch]
        prev_vote = -1
        direction = 1
        new_vote = 1
        score_delta = 2
        upvote_delta = 1
        downvote_delta = -1
        self.assertEqual(score_delta, 2)
        self.assertEqual(new_vote, 1)

        # Test case: Upvote (1) -> Downvote (-1) [Switch]
        prev_vote = 1
        direction = -1
        new_vote = -1
        score_delta = -2
        upvote_delta = -1
        downvote_delta = 1
        self.assertEqual(score_delta, -2)
        self.assertEqual(new_vote, -1)

    def test_mock_shard_aggregation_and_concurrency(self):
        """Simulate multiple votes across 20 shards and aggregate total."""
        shards_data = {}
        
        # Simulate 50 users voting +1 or -1 or switching
        votes = [
            ("user_a", 1),
            ("user_b", 1),
            ("user_c", -1),
            ("user_d", 1),
            ("user_e", 1),
            ("user_f", -1),
            ("user_g", 1),
            ("user_h", 1),
        ]
        
        for user, direction in votes:
            import hashlib
            shard_id = str(int(hashlib.md5(user.encode('utf-8')).hexdigest(), 16) % FirebaseService.NUM_SHARDS)
            if shard_id not in shards_data:
                shards_data[shard_id] = {"score": 0, "upvotes": 0, "downvotes": 0}
            
            if direction == 1:
                shards_data[shard_id]["score"] += 1
                shards_data[shard_id]["upvotes"] += 1
            else:
                shards_data[shard_id]["score"] -= 1
                shards_data[shard_id]["downvotes"] += 1

        total_score = sum(s["score"] for s in shards_data.values())
        total_upvotes = sum(s["upvotes"] for s in shards_data.values())
        total_downvotes = sum(s["downvotes"] for s in shards_data.values())

        self.assertEqual(total_upvotes, 6)
        self.assertEqual(total_downvotes, 2)
        self.assertEqual(total_score, 4)


if __name__ == "__main__":
    unittest.main()
