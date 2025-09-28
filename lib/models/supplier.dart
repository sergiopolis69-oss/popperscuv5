class Supplier {
  final int? id;
  final String name;
  final String phone;
  final String address;

  Supplier({this.id, required this.name, this.phone = '', this.address = ''});

  factory Supplier.fromMap(Map<String, dynamic> m) => Supplier(
    id: m['id'] as int?,
    name: m['name'] as String,
    phone: m['phone'] as String? ?? '',
    address: m['address'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'address': address,
  };
}
