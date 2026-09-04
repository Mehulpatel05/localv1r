enum PostCategory {
  general('General Chat', '💬'),
  services('Local Services', '🔧'),
  food('Food & Cafes', '🍲'),
  rooms('Rentals & PG', '🏠'),
  shop('Shop', '🛍️'),
  events('Events', '🎉'),
  jobs('Jobs & Referrals', '💼');

  final String label;
  final String icon;
  const PostCategory(this.label, this.icon);
}
