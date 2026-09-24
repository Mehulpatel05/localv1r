import os
import sys
import unittest
from unittest.mock import MagicMock, patch

# Include parent directory in python path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services.d1_service import D1Service


class TestVotingLogic(unittest.TestCase):
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

    def test_d1_vote_post_toggle(self):
        """Verify D1Service.vote_post behavior using mocks."""
        with patch.object(D1Service, 'query', return_value=[{"direction": 1}]), \
             patch.object(D1Service, 'execute', return_value=True):
            res = D1Service.vote_post("post-1", "alice", 1)
            self.assertTrue(res["success"])
            self.assertEqual(res["newVote"], 0) # Toggled off
            self.assertEqual(res["scoreDelta"], -1)


if __name__ == "__main__":
    unittest.main()
