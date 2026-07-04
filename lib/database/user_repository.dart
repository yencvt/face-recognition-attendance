import 'app_database.dart';

class UserRepository {
  Future<int> insertUser(String name, int age) async {
    final db = await AppDatabase.instance();
    return await db.insert('users', {'name': name, 'age': age});
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final db = await AppDatabase.instance();
    return await db.query('users');
  }

  Future<int> updateUser(int id, String name, int age) async {
    final db = await AppDatabase.instance();
    return await db.update(
      'users',
      {'name': name, 'age': age},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteUser(int id) async {
    final db = await AppDatabase.instance();
    return await db.delete('users', where: 'id = ?', whereArgs: [id]);
  }
}
