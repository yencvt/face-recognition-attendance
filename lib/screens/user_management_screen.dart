import 'package:flutter/material.dart';

import '../database/auth_user_repository.dart';
import '../services/auth_session_service.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final AuthUserRepository _repository = AuthUserRepository();
  final AuthSessionService _auth = AuthSessionService.instance;

  List<AuthUser> _users = const [];
  bool _loading = true;

  AuthUser? get _currentUser => _auth.currentUser;
  bool get _isAdmin => _auth.isAdmin;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final users = await _repository.getAllUsers();
    if (!mounted) return;
    setState(() {
      _users = users;
      _loading = false;
    });
  }

  Future<void> _changeOwnPassword(AuthUser user) async {
    final currentPasswordController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var obscureCurrentPassword = true;
    var obscurePassword = true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Doi mat khau'),
              content: SizedBox(
                width: 420,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: currentPasswordController,
                        obscureText: obscureCurrentPassword,
                        decoration: InputDecoration(
                          labelText: 'Mat khau cu',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setDialogState(() {
                                obscureCurrentPassword = !obscureCurrentPassword;
                              });
                            },
                            icon: Icon(
                              obscureCurrentPassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if ((value ?? '').isEmpty) {
                            return 'Vui long nhap mat khau cu';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Mat khau moi',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setDialogState(() {
                                obscurePassword = !obscurePassword;
                              });
                            },
                            icon: Icon(
                              obscurePassword ? Icons.visibility : Icons.visibility_off,
                            ),
                          ),
                        ),
                        validator: (value) {
                          final text = value ?? '';
                          if (text.isEmpty) {
                            return 'Vui long nhap mat khau moi';
                          }
                          if (text.length < 4) {
                            return 'Mat khau phai co it nhat 4 ky tu';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: confirmController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Nhap lai mat khau moi',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value != passwordController.text) {
                            return 'Mat khau xac nhan khong khop';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Huy'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (!(formKey.currentState?.validate() ?? false)) return;
                    try {
                      final currentPassword = currentPasswordController.text;
                      final verifiedUser = await _repository.findByCredentials(
                        user.username,
                        currentPassword,
                      );
                      if (verifiedUser == null || verifiedUser.id != user.id) {
                        throw StateError('Mat khau cu khong dung');
                      }

                      final updatedRows = await _repository.updatePassword(
                        id: user.id!,
                        password: passwordController.text,
                      );
                      if (updatedRows == 0) {
                        throw StateError('Khong cap nhat duoc mat khau');
                      }
                      if (!context.mounted) return;
                      Navigator.of(context).pop(true);
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Doi mat khau that bai: $e')),
                      );
                    }
                  },
                  child: const Text('Luu'),
                ),
              ],
            );
          },
        );
      },
    );

    currentPasswordController.dispose();
    passwordController.dispose();
    confirmController.dispose();

    if (saved == true) {
      await _loadUsers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Da cap nhat mat khau')),
      );
    }
  }

  Future<void> _openEditor({AuthUser? user}) async {
    final currentUser = _currentUser;
    final editingSelf = user != null && currentUser != null && user.id == currentUser.id;

    if (!_isAdmin) {
      if (currentUser == null) return;
      await _changeOwnPassword(currentUser);
      return;
    }

    final usernameController = TextEditingController(text: user?.username ?? '');
    final passwordController = TextEditingController(text: user?.password ?? '');
    final confirmController = TextEditingController(text: user?.password ?? '');
    final formKey = GlobalKey<FormState>();
    var obscurePassword = true;
    var selectedRole = user?.role ?? 'user';

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(user == null ? 'Them user' : 'Cap nhat user'),
              content: SizedBox(
                width: 460,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Ten dang nhap',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) return 'Vui long nhap ten dang nhap';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Quyen',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'admin', child: Text('Admin')),
                          DropdownMenuItem(value: 'user', child: Text('User')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            selectedRole = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Mat khau',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setDialogState(() {
                                obscurePassword = !obscurePassword;
                              });
                            },
                            icon: Icon(
                              obscurePassword ? Icons.visibility : Icons.visibility_off,
                            ),
                          ),
                        ),
                        validator: (value) {
                          final text = value ?? '';
                          if (text.isEmpty) return 'Vui long nhap mat khau';
                          if (text.length < 4) return 'Mat khau phai co it nhat 4 ky tu';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: confirmController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Nhap lai mat khau',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value != passwordController.text) {
                            return 'Mat khau xac nhan khong khop';
                          }
                          return null;
                        },
                      ),
                      if (editingSelf) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Ban dang sua tai khoan dang nhap hien tai.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Huy'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (!(formKey.currentState?.validate() ?? false)) return;

                    final username = usernameController.text.trim();
                    final password = passwordController.text;
                    try {
                      final existing = await _repository.findByUsername(username);

                      if (user == null && existing != null) {
                        throw StateError('User nay da ton tai');
                      }

                      if (user != null && existing != null && existing.id != user.id) {
                        throw StateError('Ten dang nhap da bi dung boi user khac');
                      }

                      if (user == null) {
                        final insertedId = await _repository.insertUser(
                          username,
                          password,
                          role: selectedRole,
                        );
                        if (insertedId <= 0) {
                          throw StateError('Khong tao duoc user');
                        }
                      } else {
                        final updatedRows = await _repository.updateUser(
                          id: user.id!,
                          username: username,
                          password: password,
                          role: selectedRole,
                        );
                        if (updatedRows == 0) {
                          throw StateError('Khong cap nhat duoc user');
                        }
                        if (user.id == _currentUser?.id) {
                          _auth.updateCurrentUser(
                            user.copyWith(
                              username: username,
                              password: password,
                              role: selectedRole,
                            ),
                          );
                        }
                      }

                      if (!context.mounted) return;
                      Navigator.of(context).pop(true);
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Luu user that bai: $e')),
                      );
                    }
                  },
                  child: const Text('Luu'),
                ),
              ],
            );
          },
        );
      },
    );

    usernameController.dispose();
    passwordController.dispose();
    confirmController.dispose();

    if (saved == true) {
      await _loadUsers();
    }
  }

  Future<void> _deleteUser(AuthUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Xoa user'),
          content: Text('Ban co chac muon xoa user "${user.username}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Huy'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Xoa'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    if (!mounted) return;
    if (_users.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Can giu it nhat 1 user de dang nhap')),
      );
      return;
    }

    await _repository.deleteUser(user.id!);
    if (user.id == _currentUser?.id) {
      _auth.logout();
      if (!mounted) return;
    }
    await _loadUsers();
  }

  Widget _roleChip(AuthUser user) {
    final isAdmin = user.isAdmin;
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(isAdmin ? 'Admin' : 'User'),
      backgroundColor: isAdmin ? Colors.orange.shade100 : Colors.blue.shade100,
      labelStyle: TextStyle(
        color: isAdmin ? Colors.orange.shade900 : Colors.blue.shade900,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildSelfServiceCard(AuthUser user) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text(user.username.isEmpty ? '?' : user.username[0].toUpperCase()),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.username,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ban dang dang nhap voi quyen ${user.isAdmin ? 'admin' : 'user'}.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                _roleChip(user),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _changeOwnPassword(user),
              icon: const Icon(Icons.lock_reset),
              label: const Text('Doi mat khau cua toi'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminView(AuthUser currentUser) {
    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Tai khoan dang nhap'),
              subtitle: Text('Tong so user: ${_users.length}'),
              trailing: FilledButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add),
                label: const Text('Them moi'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        child: Text(currentUser.username.isEmpty ? '?' : currentUser.username[0].toUpperCase()),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Tai khoan dang hoat dong',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${currentUser.username} • ${currentUser.isAdmin ? 'Admin' : 'User'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      _roleChip(currentUser),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () => _changeOwnPassword(currentUser),
                    icon: const Icon(Icons.lock_reset),
                    label: const Text('Doi mat khau cua toi'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_users.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Chua co user nao.')),
            )
          else
            ..._users.map((user) {
              final isCurrentUser = user.id == currentUser.id;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(user.username.isEmpty ? '?' : user.username[0].toUpperCase()),
                  ),
                  title: Text(user.username),
                  subtitle: Text(
                    'Cap nhat luc: ${DateTime.fromMillisecondsSinceEpoch(user.updatedAt)}',
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _roleChip(user),
                      IconButton(
                        onPressed: () => _openEditor(user: user),
                        icon: const Icon(Icons.edit),
                        tooltip: 'Cap nhat',
                      ),
                      IconButton(
                        onPressed: _users.length <= 1 ? null : () => _deleteUser(user),
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Xoa',
                      ),
                    ],
                  ),
                  selected: isCurrentUser,
                ),
              );
            }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isAdmin ? 'Quan ly user dang nhap' : 'Doi mat khau cua toi'),
        actions: [
          if (_isAdmin)
            IconButton(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.person_add_alt_1),
              tooltip: 'Them user',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : currentUser == null
              ? const Center(child: Text('Khong tim thay tai khoan dang nhap hien tai.'))
              : _isAdmin
                  ? _buildAdminView(currentUser)
                  : RefreshIndicator(
                      onRefresh: _loadUsers,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _buildSelfServiceCard(currentUser),
                        ],
                      ),
                    ),
    );
  }
}
