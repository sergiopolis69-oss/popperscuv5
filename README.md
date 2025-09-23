
# PDV Flutter (v1.1)

Cambios:
- Export/Import XML compatibles con Android 11–15 usando **selector del sistema** (SAF).
- Histograma removido de Historial; ahora hay gráficos **sencillos** en la página de **Utilidad** para ventas por día y utilidad % por día.
- Tema visual aplicado (cards redondeadas, tipografía Material 3, color seed del logo).
- Inventario con **stock** y actualización automática por ventas y compras.

### Compilar en GitHub
Incluye workflow `android-build.yml`. Cada push a `main` construye el APK y lo publica como artifact.

### Local
```bash
flutter create . --overwrite --platforms=android
flutter pub get
flutter run
```

### Android 11–15 (Descargas)
La exportación usa el **selector del sistema (SAF)** mediante `file_saver` y la importación usa `file_picker`. Funciona en Android 11–15 sin solicitar permisos de almacenamiento.
