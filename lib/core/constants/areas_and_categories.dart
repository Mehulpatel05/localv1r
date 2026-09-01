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
  traffic('Traffic', '🚦'),
  services('Local Services', '🔧'),
  food('Food & Cafes', '🍲'),
  educationJobs('Education/Jobs', '💼'),
  general('General', '💬'),
  emergency('Emergency Alert', '🚨');

  final String label;
  final String icon;
  const PostCategory(this.label, this.icon);
}
