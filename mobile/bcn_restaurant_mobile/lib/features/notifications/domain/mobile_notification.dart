class MobileNotification {
  const MobileNotification({
    required this.name,
    required this.title,
    required this.description,
    this.documentName,
    this.creation,
  });

  factory MobileNotification.fromJson(Map<String, dynamic> json) {
    return MobileNotification(
      name: json['name']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Restaurant notification',
      description: json['description']?.toString() ?? '',
      documentName: json['document_name']?.toString(),
      creation: DateTime.tryParse(json['creation']?.toString() ?? ''),
    );
  }

  final String name;
  final String title;
  final String description;
  final String? documentName;
  final DateTime? creation;
}
