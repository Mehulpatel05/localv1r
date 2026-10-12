enum PostCategory {
  general('General', '💬'),
  question('Question', '❓'),
  events('Events', '🎉'),
  alerts('Alerts', '⚠️'),
  safety('Safety', '🛡️'),
  services('Local Services', '🔧'),
  food('Restaurants', '🍲'),
  rooms('Rentals & PG', '🏠'),
  shop('Shop', '🛍️'),
  jobs('Jobs & Referrals', '💼'),
  safetyAlert('Safety Alert', '🚨');

  final String label;
  final String icon;
  const PostCategory(this.label, this.icon);
}
