class FacePerson {
  FacePerson({
    required this.id,
    required this.name,
    required this.createdAt,
    this.employeeCode = '',
    this.department = '',
    this.notes = '',
    this.imageBase64 = '',
    this.imageCropBase64 = '',
  });

  final String id;
  final String name;
  final String employeeCode;
  final String department;
  final String notes;
  final String imageBase64;
  final String imageCropBase64;
  final int createdAt;

  factory FacePerson.fromMap(Map<String, dynamic> map) {
    return FacePerson(
      id: map['id'].toString(),
      name: map['name'].toString(),
      employeeCode: map['employee_code']?.toString() ?? '',
      department: map['department']?.toString() ?? '',
      notes: map['notes']?.toString() ?? '',
      imageBase64: map['image_base64']?.toString() ?? '',
      imageCropBase64: map['image_crop_base64']?.toString() ?? '',
      createdAt: (map['created_at'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'employee_code': employeeCode,
      'department': department,
      'notes': notes,
      'image_base64': imageBase64,
      'image_crop_base64': imageCropBase64,
      'created_at': createdAt,
    };
  }
}