enum VadodaraArea {
  alkapuri('Alkapuri'),
  manjalpur('Manjalpur'),
  gotri('Gotri'),
  sayajigunj('Sayajigunj'),
  karelibaug('Karelibaug'),
  waghodia('Waghodia'),
  harni('Harni'),
  vasna('Vasna'),
  general('Vadodara — General');

  final String displayName;
  const VadodaraArea(this.displayName);
}

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
