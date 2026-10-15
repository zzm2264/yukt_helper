class User {
  final String name;
  final String avatar;
  final String phone;
  final String uid;
  final String school;
  final String platform;
  String remark;
  Map<String, String>? imAccount;
  Map<String, dynamic>? deviceInfo;
  bool status;

  User({
    required this.name,
    required this.avatar,
    required this.phone,
    required this.uid,
    this.school = '',
    this.platform = 'rainClassroom',
    this.remark = '',
    this.imAccount,
    this.deviceInfo,
    this.status = true
  });

  static String normalizePhone(dynamic raw) {
    if (raw == null) return '未知手机号';
    var p = raw.toString().trim();
    if (p.startsWith('+86')) {
      p = p.substring(3).trim();
    }
    return p.isEmpty ? '未知手机号' : p;
  }

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
        name: json['name'] ?? '未知用户',
        avatar: json['avatar'] ?? '',
        phone: normalizePhone(json['phone']),
        uid: json['uid'] ?? '0',
        school: json['school'] ?? '',
        platform: json['platform'] ?? 'rainClassroom',
        remark: json['remark'] ?? '',
        imAccount: json['imAccount'] != null ?
        Map<String, String>.from(json['imAccount']) : null,
        deviceInfo: json['deviceInfo'] != null ?
        Map<String, dynamic>.from(json['deviceInfo']) : null,
        status: json['status'] ?? true
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'avatar': avatar,
      'phone': phone,
      'uid': uid,
      'school': school,
      'platform': platform,
      'remark': remark,
      'imAccount': imAccount,
      'deviceInfo': deviceInfo,
      'status': status
    };
  }

  static User get empty => User(
      name: '',
      avatar: '',
      phone: '',
      uid: '',
      school: '',
      remark: ''
  );

  void setRemark(String newRemark) {
    remark = newRemark;
  }

  void setStatus(bool newStatus) {
    status = newStatus;
  }

  bool get isChaoxing => false;
  bool get isRainClassroom => true;
}