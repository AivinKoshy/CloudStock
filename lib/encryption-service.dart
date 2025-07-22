import 'package:encrypt/encrypt.dart';

class EncryptionService {
  // Use a fixed key and IV for simplicity
  static final Key _key = Key.fromLength(32); // AES-256
  static final IV _iv = IV.fromLength(16);
  
  static String encrypt(String text) {
    final encrypter = Encrypter(AES(_key));
    final encrypted = encrypter.encrypt(text, iv: _iv);
    return encrypted.base64;
  }
  
  static String decrypt(String encryptedText) {
    try {
      final encrypter = Encrypter(AES(_key));
      final decrypted = encrypter.decrypt64(encryptedText, iv: _iv);
      return decrypted;
    } catch (e) {
      // If decryption fails (perhaps it wasn't encrypted), return the original
      return encryptedText;
    }
  }
}
