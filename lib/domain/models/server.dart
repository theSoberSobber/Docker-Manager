class Server {
  final String id;
  final String name;
  final String ip;
  final int port;
  final String username;
  final String? password;
  final String? privateKey;
  final String? passphrase; // Passphrase for encrypted private keys
  final String? dockerCliPath; // Optional: if null, uses global setting
  final bool notificationsEnabled; // Whether push notifications are set up for this server

  Server({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.username,
    this.password,
    this.privateKey,
    this.passphrase,
    this.dockerCliPath,
    this.notificationsEnabled = false,
  });

  // Convert Server to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ip': ip,
      'port': port,
      'username': username,
      'password': password,
      'privateKey': privateKey,
      'passphrase': passphrase,
      'dockerCliPath': dockerCliPath,
      'notificationsEnabled': notificationsEnabled,
    };
  }

  // Create Server from JSON
  factory Server.fromJson(Map<String, dynamic> json) {
    return Server(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Unnamed Server', // Fallback for existing servers
      ip: json['ip'] as String,
      port: json['port'] as int,
      username: json['username'] as String,
      password: json['password'] as String?,
      privateKey: json['privateKey'] as String?,
      passphrase: json['passphrase'] as String?,
      dockerCliPath: json['dockerCliPath'] as String?,
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? false,
    );
  }

  // Create copy with updated fields
  Server copyWith({
    String? id,
    String? name,
    String? ip,
    int? port,
    String? username,
    String? password,
    String? privateKey,
    String? passphrase,
    String? dockerCliPath,
    bool? notificationsEnabled,
  }) {
    return Server(
      id: id ?? this.id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      privateKey: privateKey ?? this.privateKey,
      passphrase: passphrase ?? this.passphrase,
      dockerCliPath: dockerCliPath ?? this.dockerCliPath,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    );
  }

  @override
  String toString() {
    return 'Server(id: $id, name: $name, ip: $ip, port: $port, username: $username, notifications: $notificationsEnabled)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Server && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
