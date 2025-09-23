
class Customer {
  /// ID del cliente == teléfono
  final String phone;
  final String name;
  final String address;

  Customer({required this.phone, required this.name, required this.address});

  Map<String, Object?> toMap() => {
    'phone': phone,
    'name': name,
    'address': address,
  };

  factory Customer.fromMap(Map<String, Object?> map) => Customer(
    phone: map['phone'] as String,
    name: map['name'] as String,
    address: map['address'] as String,
  );
}
