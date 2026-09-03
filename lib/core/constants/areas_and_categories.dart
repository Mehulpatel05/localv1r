enum PostCategory {
  services('Local Services', '🔧'),
  food('Food & Cafes', '🍲'),
  rooms('Rooms', '🏠'),
  shop('Shop', '🛍️'),
  events('Events', '🎉'),
  jobs('Jobs & Referrals', '💼');

  final String label;
  final String icon;
  const PostCategory(this.label, this.icon);
}
