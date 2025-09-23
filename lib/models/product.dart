
class Product {
  final int? id;
  final String name;
  final String category;
  final double salePrice;
  final double lastPurchasePrice;
  final String? lastPurchaseDate;
  final int stock;

  Product({
    this.id,
    required this.name,
    required this.category,
    required this.salePrice,
    required this.lastPurchasePrice,
    this.lastPurchaseDate,
    this.stock = 0,
  });

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'category': category,
    'salePrice': salePrice,
    'lastPurchasePrice': lastPurchasePrice,
    'lastPurchaseDate': lastPurchaseDate,
    'stock': stock,
  };

  factory Product.fromMap(Map<String, Object?> map) => Product(
    id: map['id'] as int?,
    name: map['name'] as String,
    category: map['category'] as String,
    salePrice: (map['salePrice'] as num).toDouble(),
    lastPurchasePrice: (map['lastPurchasePrice'] as num).toDouble(),
    lastPurchaseDate: map['lastPurchaseDate'] as String?,
    stock: (map['stock'] as num?)?.toInt() ?? 0,
  );
}
